require 'reapack/index/gem_version'

require 'addressable'
require 'colorize'
require 'fileutils'
require 'gitable'
require 'io/console'
require 'metaheader'
require 'nokogiri'
require 'optparse'
require 'pandoc-ruby'
require 'pathname'
require 'rugged'
require 'shellwords'
require 'stable_sort'
require 'time'

require 'reapack/index/cdetector'
require 'reapack/index/cli'
require 'reapack/index/cli/options'
require 'reapack/index/git'
require 'reapack/index/metadata'
require 'reapack/index/named_node'
require 'reapack/index/package'
require 'reapack/index/parsers'
require 'reapack/index/provides'
require 'reapack/index/source'
require 'reapack/index/version'

class ReaPack::Index
  Error = Class.new RuntimeError

  PKG_TYPES = {
    script: %w{lua eel py},
    extension: %w{ext},
    effect: %w{jsfx},
    data: %w{data},
  }.freeze

  WITH_MAIN = [:script, :effect].freeze

  PROVIDES_VALIDATOR = proc {|value|
    begin
      Provides.parse_each(value).to_a and nil
    rescue Error => e
      e.message
    end
  }

  HEADER_RULES = {
    # package-wide tags
    :version => [
      MetaHeader::REQUIRED, MetaHeader::VALUE, MetaHeader::SINGLELINE, /\d/],

    # version-specific tags
    :author => [MetaHeader::VALUE, MetaHeader::SINGLELINE],
    :changelog => [MetaHeader::VALUE],
    :provides => [MetaHeader::VALUE, PROVIDES_VALIDATOR]
  }.freeze

  FS_ROOT = File.expand_path('/').freeze

  attr_reader :path, :url_template
  attr_accessor :amend, :files, :time

  class << self
    def is_type?(input)
      PKG_TYPES.has_key? input&.to_sym
    end

    def type_of(path)
      # don't treat files in the root directory as packages
      # because they don't have a category
      return if File.dirname(path) == '.'

      ext = File.extname(path)[1..-1]
      PKG_TYPES.find {|_, v| v.include? ext }&.first if ext
    end

    alias :is_package? :type_of

    def resolve_type(input)
      PKG_TYPES
        .find {|name, exts| input.to_sym == name || exts.include?(input.to_s) }
        &.first
    end
  end

  def initialize(path)
    @amend = false
    @changes = {}
    @changed_nodes = []
    @files = []
    @path = path

    @cdetector = ConflictDetector.new

    if File.exist? path
      begin
        # noblanks: don't preserve the original white spaces
        # so we always output a neat document
        @doc = File.open(path) {|file| Nokogiri::XML file, &:noblanks }
      rescue Nokogiri::XML::SyntaxError
      end

      unless @doc&.root&.name == 'index'
        raise Error, "'#{path}' is not a ReaPack index file"
      end

      @cdetector.load_xml @doc.root
    else
      @dirty = true
      @is_new = true

      @doc = Nokogiri::XML::Document.new
      @doc.root = Nokogiri::XML::Node.new 'index', @doc
    end

    @doc.root[:version] = 1
    @doc.encoding = 'utf-8'

    @metadata = Metadata.new @doc.root
  end

  def scan(path, contents)
    type = self.class.type_of path
    return unless type

    # variables to restore if an error occur
    backups = Hash[[:@doc, :@cdetector].map {|var|
      [var, instance_variable_get(var).clone]
    }]

    mh = MetaHeader.new contents

    if mh[:noindex]
      remove path
      return
    end

    if errors = mh.validate(HEADER_RULES)
      raise Error, errors.join("\n")
    end

    cat, pkg = package_for path

    cselector = @cdetector[pkg.type = type, path]

    pkg.version mh[:version] do |ver|
      next unless ver.is_new? || @amend

      # store the version name for make_url
      # TODO: split in a new class, along with make_url?
      @currentVersion = ver.name
      @currentPkg = pkg

      ver.author = mh[:author]
      ver.time = @time if @time && ver.is_new?
      ver.changelog = mh[:changelog]

      ver.replace_sources do
        cselector.clear
        sources = parse_provides mh[:provides], pkg

        if WITH_MAIN.include?(type) && sources.none? {|src| src.file.nil? }
          # add the package itself as a source
          src = Source.new make_url(path)
          sources.unshift src

          cselector.push src.platform, path
        end

        sources.each {|src| ver.add_source src }
      end
    end

    if cons = cselector.resolve
      raise Error, cons.first
    end

    log_change 'new category', 'new categories' if cat.is_new?

    if pkg.modified? && !@changed_nodes.include?(pkg.node)
      log_change "#{pkg.is_new? ? 'new' : 'modified'} package"
      @changed_nodes << pkg.node
    end

    pkg.versions.each {|ver|
      if ver.modified? && !@changed_nodes.include?(ver.node)
        log_change "#{ver.is_new? ? 'new' : 'modified'} version"
        @changed_nodes << ver.node
      end
    }

    bump_commit
  rescue Error
    backups.each {|var, value| instance_variable_set var, value }
    raise
  end
  
  def remove(path)
    cat, pkg = package_for path, false
    return unless pkg

    @cdetector[pkg.type, path].clear

    pkg.remove
    cat.remove if cat.empty?

    bump_commit
    log_change 'removed package'
  end

  def links(type)
    @metadata.links type
  end

  def eval_link(type, string)
    if string.index('-') == 0
      @metadata.remove_link type, string[1..-1]
      log_change "removed #{type} link"
      return
    end

    link = @metadata.push_link type, *string.split('=', 2)

    if link.is_new?
      log_change "new #{type} link"
    elsif link.modified?
      log_change "modified #{type} link"
    end
  end

  def description
    @metadata.description
  end

  def description=(content)
    old = @metadata.description
    @metadata.description = content

    log_change 'modified metadata' if old != @metadata.description
  end

  def url_template=(tpl)
    return @url_template = nil if tpl.nil?

    uri = Addressable::URI.parse tpl
    uri.normalize!

    unless (uri.request_uri || uri.path).include? '$path'
      raise Error, "missing $path placeholder in '#{tpl}'"
    end

    unless %w{http https file}.include? uri.scheme
      raise Addressable::URI::InvalidURIError
    end

    @url_template = tpl
  rescue Addressable::URI::InvalidURIError
    raise Error, "invalid template '#{tpl}'"
  end

  def version
    @doc.root[:version].to_i
  end

  def name
    @doc.root[:name].to_s
  end

  def name=(newName)
    if !/\A[^~#%&*{}\\:<>?\/+|"]+\Z/.match(newName) || /\A\.+\Z/.match(newName)
      raise Error, "invalid name '#{newName}'"
    end

    oldName = name
    @doc.root['name'] = newName
    log_change 'modified metadata' if oldName != newName
  end

  def commit
    @commit ||= @doc.root[:commit]
  end

  attr_writer :commit

  def write(path)
    sort @doc.root

    FileUtils.mkdir_p File.dirname(path)
    File.binwrite path, @doc.to_xml
  end

  def write!
    write @path

    @is_new = @dirty = false
    @changes.clear
  end

  def modified?
    !!@dirty
  end

  def changelog
    list = []

    @changes.each_pair {|type, data|
      count, plural = data
      list << "#{count} #{count != 1 ? plural : type}"
    }

    list << 'empty index' if @is_new && Category.find_all(@doc.root).empty?

    list.join ', '
  end

  def make_url(path, template = nil)
    unless template
      unless @url_template
        raise Error, 'unable to generate download links: empty url template'
      end

      unless @files.include? path
        raise Error, "file not found '#{path}'"
      end
    end

    (template || @url_template)
      .sub('$path', path)
      .sub('$commit', commit || 'master')
      .sub('$version', @currentVersion.to_s)
      .sub('$package', @currentPkg&.path.to_s)
  end

  def clear
    Category.find_all(@doc.root).each {|cat| cat.remove }
    clear_cdetector
  end

  def clear_cdetector
    @cdetector.clear
  end

  def self.expand(filepath, basedir)
    expanded = File.expand_path filepath, FS_ROOT + basedir
    expanded[0...FS_ROOT.size] = ''
    expanded
  end

private
  def log_change(desc, plural = nil)
    @dirty = true

    @changes[desc] ||= [0, plural || desc + 's']
    @changes[desc][0] += 1
  end

  def package_for(path, create = true)
    cat_name = File.dirname path
    pkg_name = File.basename path

    cat = Category.fetch cat_name, @doc.root, create
    pkg = Package.fetch pkg_name, cat&.node, create

    [cat, pkg]
  end

  def parse_provides(provides, pkg)
    pathdir = Pathname.new pkg.category

    Provides.parse_each(provides).map {|line|
      line.file_pattern = pkg.name if line.file_pattern == '.'

      expanded = self.class.expand line.file_pattern, pkg.category
      cselector = @cdetector[line.type || pkg.type, pkg.path]

      if expanded == pkg.path
        # always resolve path even when an url template is set
        files = [expanded]
      elsif line.url_template.nil?
        files = @files.select {|f|
          File.fnmatch expanded, f, File::FNM_PATHNAME | File::FNM_EXTGLOB
        }
        raise Error, "file not found '#{line.file_pattern}'" if files.empty?
      else
        # use the relative path for external urls
        files = [line.file_pattern]
      end

      files.map {|file|
        src = Source.new make_url(file, line.url_template)
        src.platform = line.platform
        src.type = line.type

        cselector.push src.platform, line.url_template ? expanded : file

        if file != pkg.path
          if line.url_template
            src.file = file
          else
            src.file = Pathname.new(file).relative_path_from(pathdir).to_s
          end
        end

        src
      }
    }.flatten
  end

  def sort(node)
    node.element_children.map {|n| sort n }
    return if node.name == Package.tag

    sorted = node.element_children
      .stable_sort_by {|n| n[:name].to_s.downcase }
      .stable_sort_by {|n| n.name.downcase }

    sorted.each {|n| node << n }
  end

  def bump_commit
    sha1 = commit()

    if sha1.nil?
      @doc.root.remove_attribute 'commit'
    else
      @doc.root['commit'] = sha1
    end
  end
end

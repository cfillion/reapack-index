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
require 'time'

require 'reapack/index/cli'
require 'reapack/index/cli/options'
require 'reapack/index/metadata'
require 'reapack/index/named_node'
require 'reapack/index/package'
require 'reapack/index/parsers'
require 'reapack/index/version'

class ReaPack::Index
  Error = Class.new RuntimeError

  FILE_TYPES = {
    'lua'  => :script,
    'eel'  => :script,
    'py'   => :script,
    'ext'  => :extension,
    'jsfx' => :effect,
  }.freeze

  WITH_MAIN = [:script, :effect].freeze

  PROVIDES_REGEX = /
    \A
    ( \[ \s* (?<platform> .+? ) \s* \] )?
    \s*
    (?<file> .+?)
    ( \s+ (?<url> (?:file|https?):\/\/.+ ) )?
    \z
  /x.freeze

  PROVIDES_VALIDATOR = proc {|value|
    begin
      files = value.lines.map {|l|
        m = l.chomp.match PROVIDES_REGEX
        Source.validate_platform m[:platform]
        [m[:platform], m[:file]]
      }
      dup = files.detect {|f| files.count(f) > 1 }
      "duplicate file (%s)" % dup[1] if dup
    rescue Error => e
      e.message
    end
  }.freeze

  HEADER_RULES = {
    # package-wide tags
    :version => /\A(?:[^\d]*\d{1,4}[^\d]*){1,4}\z/,

    # version-specific tags
    :author => [MetaHeader::OPTIONAL, /\A[^\n]+\z/],
    :changelog => [MetaHeader::OPTIONAL, /.+/],
    :provides => [MetaHeader::OPTIONAL, PROVIDES_VALIDATOR]
  }.freeze

  FS_ROOT = File.expand_path('/').freeze

  attr_reader :path, :url_template
  attr_accessor :amend, :files, :time

  def self.type_of(path)
    ext = File.extname(path)[1..-1]
    FILE_TYPES[ext]
  end

  def self.validate_file(path)
    mh = MetaHeader.from_file path
    return if mh[:noindex]

    mh.validate HEADER_RULES
  end

  def initialize(path)
    @amend = false
    @changes = {}
    @changed_nodes = []
    @files = []
    @path = path

    if File.exist? path
      # noblanks: don't preserve the original white spaces
      # so we always output a neat document
      @doc = File.open(path) {|file| Nokogiri::XML file, &:noblanks }
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

    mh = MetaHeader.new contents

    backup = @doc.root.dup

    if mh[:noindex]
      remove path
      return
    end

    if errors = mh.validate(HEADER_RULES)
      prefix = errors.size == 1 ? "\x20" : "\n\x20\x20"
      raise Error, 'invalid metadata:%s' %
        [prefix + errors.join(prefix)]
    end

    cat, pkg = find path
    pkg.type = type.to_s

    pkg.version mh[:version] do |ver|
      next unless ver.is_new? || @amend

      # store the version name for make_url
      @currentVersion = ver.name

      ver.author = mh[:author]
      ver.time = @time if @time && ver.is_new?
      ver.changelog = mh[:changelog]

      ver.replace_sources do
        sources = parse_provides mh[:provides], path

        if WITH_MAIN.include?(type) && sources.none? {|src| src.file.nil? }
          # add the package itself as a source
          sources.unshift Source.new nil, nil, make_url(path)
        end

        sources.each {|src| ver.add_source src }
      end
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
    @doc.root = backup
    raise
  end
  
  def remove(path)
    cat, pkg = find path, false
    return unless pkg

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
      raise Error, "$path placeholder is missing: #{tpl}"
    end

    unless %w{http https file}.include? uri.scheme
      raise Addressable::URI::InvalidURIError
    end

    @url_template = uri.to_s.freeze
  rescue Addressable::URI::InvalidURIError
    raise Error, "invalid URL or scheme: #{tpl}"
  end

  def version
    @doc.root[:version].to_i
  end

  def name
    @doc.root[:name].to_s
  end

  def name=(newName)
    if !/\A[^~#%&*{}\\:<>?\/+|"]+\Z/.match(newName) || /\A\.+\Z/.match(newName)
      raise Error, "Invalid name: '#{newName}'"
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
    @doc.root.element_children.each {|n| sort n if n.name == 'category' }
    sort @doc.root

    FileUtils.mkdir_p File.dirname(path)
    File.write path, @doc.to_xml
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
    if template.nil?
      unless @url_template
        raise Error, 'unable to generate download links: ' \
          'no url template set'
      end

      unless @files.include? path
        raise Error, "#{path}: No such file or directory"
      end
    end

    (template || @url_template)
      .sub('$path', path)
      .sub('$commit', commit || 'master')
      .sub('$version', @currentVersion.to_s)
  end

private
  def log_change(desc, plural = nil)
    @dirty = true

    @changes[desc] ||= [0, plural || desc + 's']
    @changes[desc][0] += 1
  end

  def dirname(path)
    name = File.dirname path
    name == '.' ? nil : name
  end

  def find(path, create = true)
    cat_name = dirname(path) || 'Other'
    pkg_name = File.basename path

    cat = Category.get cat_name, @doc.root, create
    pkg = Package.get pkg_name, cat && cat.node, create

    [cat, pkg]
  end

  def parse_provides(provides, path)
    return [] unless provides.is_a? String

    basename = File.basename path
    basedir = dirname(path).to_s
    pathdir = Pathname.new basedir

    sources = provides.lines.map {|line|
      m = line.chomp.match PROVIDES_REGEX
      platform, pattern, url_tpl = m[:platform], m[:file], m[:url]

      pattern = basename if pattern == '.'

      absolute = File.expand_path pattern, FS_ROOT + basedir
      absolute[0...FS_ROOT.size] = ''

      if absolute == path
        # always resolve path even when an url template is set
        files = [absolute]
      elsif url_tpl.nil?
        files = @files.select {|f| File.fnmatch absolute, f, File::FNM_PATHNAME }
        raise Error, "#{absolute}: No such file or directory" if files.empty?
      else
        # use the relative path for external urls
        files = [pattern]
      end

      files.map {|file|
        url = make_url file, url_tpl

        if file == path
          file = nil
        elsif url_tpl.nil?
          file = Pathname.new(file).relative_path_from(pathdir).to_s
        end

        Source.new platform, file, url
      }
    }.flatten
  end

  def sort(node)
    sorted = node.children.sort_by{|n| n[:name].to_s }.sort_by {|n| n.name }
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

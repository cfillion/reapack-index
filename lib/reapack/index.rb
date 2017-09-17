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
require 'reapack/index/scanner'
require 'reapack/index/source'
require 'reapack/index/version'

class ReaPack::Index
  Error = Class.new RuntimeError

  PKG_TYPES = {
    script: %w{lua eel py},
    extension: %w{ext},
    effect: %w{jsfx},
    data: %w{data},
    theme: %w{theme},
    langpack: %w{reaperlangpack},
    webinterface: %w{www},
  }.freeze

  FS_ROOT = File.expand_path('/').freeze

  NAME_REGEX = /\A[^*\\:<>?\/|"[:cntrl:]]+\Z/.freeze
  NAME_INVALID = /\A(:?[\.\x20].*|.+[\.\x20]|CLOCK\$|COM\d|LPT\d)\Z/i.freeze

  attr_reader :path, :url_template, :cdetector
  attr_accessor :amend, :commit, :files, :time, :strict
  attr_accessor :auto_bump_commit

  class << self
    def is_type?(input)
      PKG_TYPES.has_key? input&.to_sym
    end

    def type_of(path)
      # don't treat files in the root directory as packages
      # because they don't have a category

      if File.dirname(path) != '.' && (ext = File.extname(path)[1..-1])
        ext.downcase!
        PKG_TYPES.find {|_, v| v.include? ext }&.first
      end
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
    @auto_bump_commit = true

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

    mh = MetaHeader.parse contents
    mh.strict = @strict

    if mh[:noindex]
      remove path
      return
    end

    # variables to restore if an error occur
    backups = Hash[[:@doc, :@cdetector].map {|var|
      [var, instance_variable_get(var).clone]
    }]

    cat, pkg = package_for path
    pkg.type = type

    scanner = Scanner.new cat, pkg, mh, self

    begin
      scanner.run
    rescue Error
      backups.each {|var, value| instance_variable_set var, value }
      raise
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

    bump_commit if @auto_bump_commit
  end

  def remove(path)
    cat, pkg = package_for path, false
    return unless pkg

    @cdetector[path].clear

    pkg.remove
    cat.remove if cat.empty?

    bump_commit if @auto_bump_commit
    log_change 'removed package'
  end

  def links(type)
    @metadata.links type
  end

  def eval_link(type, input)
    if input.index('-') == 0
      @metadata.remove_link type, input[1..-1]
      log_change "removed #{type} link"
      return
    end

    link = @metadata.push_link type, *Link.split(input)

    if link.is_new?
      log_change "new #{type} link"
    elsif link.modified?
      log_change "modified #{type} link"
    end
  end

  def about
    @metadata.about
  end

  def about=(content)
    old = @metadata.about
    @metadata.about = content

    log_change 'modified metadata' if old != @metadata.about
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
    if !NAME_REGEX.match(newName) || NAME_INVALID.match(newName)
      raise Error, "invalid name '#{newName}'"
    end

    oldName = name
    @doc.root['name'] = newName
    log_change 'modified metadata' if oldName != newName
  end

  def last_commit
    @doc.root[:commit]
  end

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

  def clear
    Category.find_all(@doc.root).each {|cat| cat.remove }
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

  def sort(node)
    node.element_children.map {|n| sort n }

    sorted = node.element_children
      .stable_sort_by {|n|
        if n.name == Version.tag
          '' # don't sort version tags by name attribute value
        else
          n[:name].to_s.downcase
        end
      }
      .stable_sort_by {|n| n.name.downcase }

    sorted.each {|n| node << n }
  end

  def bump_commit
    sha1 = @commit || last_commit

    if sha1.nil?
      @doc.root.remove_attribute 'commit'
    else
      @doc.root['commit'] = sha1
    end
  end
end

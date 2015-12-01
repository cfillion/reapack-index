require 'reapack/index/version'

require 'git'
require 'io/console'
require 'metaheader'
require 'nokogiri'

require 'reapack/index/indexer'

class ReaPack::Index
  FILE_TYPES = {
    'lua' => :script,
    'eel' => :script,
  }.freeze

  HEADER_RULES = {
    :version => /\A(?:[^\d]*\d{1,4}[^\d]*){1,4}\z/,
    :changelog => [MetaHeader::OPTIONAL, /.+/],
  }.freeze

  SOURCE_HOSTS = {
    /\Agit@github\.com:([^\/]+)\/(.+)\.git\z/ =>
      'https://github.com/\1/\2/raw/$commit/$path',
    /\Ahttps:\/\/github\.com\/([^\/]+)\/(.+)\.git\z/ =>
      'https://github.com/\1/\2/raw/$commit/$path',
  }.freeze

  attr_reader :path, :source_pattern

  def self.type_of(path)
    ext = File.extname(path)[1..-1]
    FILE_TYPES[ext]
  end

  def self.source_for(url)
    SOURCE_HOSTS.each_pair {|regex, pattern|
      return url.gsub regex, pattern if url =~ regex
    }

    nil
  end

  def self.validate_file(path)
    mh = MetaHeader.from_file path
    mh.validate HEADER_RULES
  end

  def initialize(path)
    @path = path
    @changes = {}

    if File.exists? path
      @dirty = false

      @doc = Nokogiri::XML File.open(path) do |config|
        # don't add extra blank lines
        # (because they don't go away when removing nodes)
        config.noblanks
      end
    else
      @dirty = true

      @doc = Nokogiri::XML::Document.new
      @doc.root = Nokogiri::XML::Node.new 'index', @doc
      self.version = 1
    end
  end

  def scan(path, contents)
    type = self.class.type_of path
    return unless type

    mh = MetaHeader.new contents

    if errors = mh.validate(HEADER_RULES)
      raise RuntimeError, "Invalid metadata in #{path}:\n#{errors.inspect}"
    end

    cat, pkg = find path

    if pkg[:type].to_s != type.to_s
      pkg[:type] = type
      @dirty = true
    end

    ver = add_version pkg, mh[:version]
    add_changelog ver, mh[:changelog]
    add_sources ver, mh, path

    log_change 'updated script' if modified?
  end
  
  def delete(path)
    cat, pkg = find path, false
    return unless pkg

    pkg.remove
    cat.remove if cat.element_children.empty?

    log_change "removed #{pkg[:type]}"
  end

  def source_pattern=(pattern)
    return if pattern.nil?
    raise ArgumentError, '$path not in pattern' unless pattern.include? '$path'

    @source_pattern = pattern
  end

  def version
    @doc.root[:version].to_i
  end

  def version=(ver)
    @doc.root[:version] = ver
  end

  def commit
    @doc.root[:commit]
  end

  def commit=(sha1)
    @doc.root[:commit] = sha1
  end

  def write(path)
    File.write path, @doc.to_xml
  end

  def write!
    write @path

    @dirty = false
    @changes.clear
  end

  def modified?
    @dirty
  end

  def changelog
    list = []

    @changes.each_pair {|type, data|
      count, plural = data
      list << "#{count} #{count != 1 ? plural : type}"
    }

    list.empty? ? nil : list.join(', ')
  end

private
  def log_change(type, plural = nil)
    @dirty = true

    @changes[type] ||= [0, plural || type + 's']
    @changes[type][0] += 1
  end

  def find(path, create = true)
    cat_name = File.dirname path
    cat_name = 'Other' if cat_name == '.'

    pkg_name = File.basename path

    cat = add_category cat_name, create
    pkg = cat ? add_package(cat, pkg_name, create) : nil

    [cat, pkg]
  end

  def add_category(name, create = true)
    cat_node = @doc.root.element_children.select {|node|
      node.name == 'category' && node[:name] == name
    }.first

    if cat_node.nil? && create
      log_change 'new category', 'new categories'

      cat_node = Nokogiri::XML::Node.new 'category', @doc
      cat_node[:name] = name
      cat_node.parent = @doc.root
    end

    cat_node
  end

  def add_package(cat, name, create = true)
    pkg_node = cat.element_children.select {|node|
      node.name == 'reapack' && node[:name] == name
    }.first

    if pkg_node.nil? && create
      log_change 'new package'

      pkg_node = Nokogiri::XML::Node.new 'reapack', @doc
      pkg_node[:name] = name
      pkg_node.parent = cat
    end

    pkg_node
  end

  def add_version(pkg, name)
    ver_node = pkg.element_children.select {|node|
      node.name == 'version' && node[:name] == name
    }.first

    unless ver_node
      log_change 'new version'

      ver_node = Nokogiri::XML::Node.new 'version', @doc
      ver_node[:name] = name
      ver_node.parent = pkg
    end

    ver_node
  end

  def add_changelog(ver, log)
    cl_node = ver.element_children.select {|node|
      node.name == 'changelog'
    }.first

    cdata = nil

    if log.to_s.empty?
      if cl_node
        cl_node.remove
        @dirty = true
      end

      return
    elsif cl_node.nil?
      cl_node = Nokogiri::XML::Node.new 'changelog', @doc
      cl_node.parent = ver
      @dirty = true
    elsif cdata = cl_node.children.first
      @dirty = true if cdata.content != log
      cdata.remove
    end

    cdata = Nokogiri::XML::CDATA.new @doc, log
    cdata.parent = cl_node

    cl_node
  end

  def add_sources(ver, mh, path)
    if !@source_pattern
      raise RuntimeError, "Source pattern is unset "\
        "and the package doesn't specify its source"
    end

    old_sources = []
    ver.element_children.each {|node|
      next unless node.name == 'source'
      old_sources << parse_source(node)
      node.remove
    }

    source = add_source ver, :all, @source_pattern
      .sub('$path', path)
      .sub('$commit', @commit || 'master')

    old_sources.delete parse_source(source)

    @dirty = true unless old_sources.empty?
  end

  def add_source(ver, platform, url)
    node = Nokogiri::XML::Node.new 'source', @doc
    node[:platform] = platform
    node.content = url
    node.parent = ver
    node
  end

  def parse_source(node)
    [node[:platform].to_s, node.content]
  end
end

require 'reapack/index/version'

require 'metaheader'
require 'nokogiri'

class ReaPack::Index
  FILE_TYPES = {
    'lua' => :script,
    'eel' => :script,
  }.freeze

  HEADER_RULES = {
    :author => MetaHeader::REQUIRED,
    :version => /\A(?:[^\d]*\d+[^\d]*){1,4}\z/,
    :changelog => MetaHeader::OPTIONAL,
  }.freeze

  SOURCE_HOSTS = {
    /\Agit@github\.com:([^\/]+)\/(.+)\.git\z/ =>
      'https://github.com/\1/\2/raw/master/$path',
    /\Ahttps:\/\/github\.com\/([^\/]+)\/(.+)\.git\z/ =>
      'https://github.com/\1/\2/raw/master/$path',
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
    @dirty = false

    if File.exists? path
      @doc = Nokogiri::XML File.open(path) do |config|
        # don't add extra blank lines
        # (because they don't go away when removing nodes)
        config.noblanks
      end
    else
      @doc = Nokogiri::XML::Document.new
      @doc.root = Nokogiri::XML::Node.new 'index', @doc
      self.version = 1
    end
  end

  def scan(path, contents)
    type, cat, pkg = find path
    return unless type

    mh = MetaHeader.new contents

    if errors = mh.validate(HEADER_RULES)
      raise RuntimeError, "Invalid metadata in #{path}:\n#{errors.inspect}"
    end

    if pkg[:type] != type
      pkg[:type] = type
      @dirty = true
    end

    if pkg[:author] != mh[:author]
      pkg[:author] = mh[:author]
      @dirty = true
    end

    ver = add_version pkg, mh[:version]
    add_changelog ver, mh[:changelog]

    if !@source_pattern
      raise RuntimeError, "source pattern is unset "\
        "and the package doesn't specify it's source"
    end

    # remove existing sources
    ver.element_children.each {|node|
      next unless node.name == 'source'
      node.remove
    }

    add_source ver, :all, @source_pattern.sub('$path', path)

    log_change 'script' if modified?
  end
  
  def delete(path)
    type, cat, pkg = find path
    return unless pkg
    puts 'delete request!'
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

  def find(path)
    type = self.class.type_of path
    return unless type

    cat_name = File.dirname path
    pkg_name = File.basename path

    cat = add_category cat_name
    pkg = add_package cat, pkg_name

    [type, cat, pkg]
  end

  def add_category(name)
    cat_node = @doc.root.element_children.select {|node|
      node.name == 'category' && node[:name] == name
    }.first

    unless cat_node
      log_change 'new category', 'new categories'

      cat_node = Nokogiri::XML::Node.new 'category', @doc
      cat_node[:name] = name
      cat_node.parent = @doc.root
    end

    cat_node
  end

  def add_package(cat, name)
    pkg_node = cat.element_children.select {|node|
      node.name == 'reapack' && node[:name] == name
    }.first

    unless pkg_node
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
      cl_node.remove if cl_node
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

  def add_source(ver, platform, url)
    node = Nokogiri::XML::Node.new 'source', @doc
    node[:platform] = platform
    node.content = url
    node.parent = ver

    @dirty = true
  end
end

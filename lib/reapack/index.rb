require 'reapack/index/version'

require 'metaheader'
require 'nokogiri'

class ReaPack::Index
  FILE_TYPES = {
    'lua' => :script,
    'eel' => :script,
  }.freeze

  attr_reader :path

  def self.type_of(path)
    ext = File.extname(path)[1..-1]
    FILE_TYPES[ext]
  end

  def initialize(path)
    @path = path
    @changes = {}

    if File.exists? path
      @doc = File.open(path) {|f| Nokogiri::XML(f) }
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

    pkg[:type] = type
    pkg[:author] = mh[:author]

    ver = version_node pkg, mh[:version]
  end
  
  def delete(path)
    type, cat, pkg = find path
    return unless pkg
    puts 'delete request!'
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
    @changes[type] ||= [0, plural || type + 's']
    @changes[type][0] += 1
  end

  def find(path)
    type = self.class.type_of path
    return unless type

    cat_name = File.dirname path
    pkg_name = File.basename path

    cat = category_node cat_name
    pkg = package_node cat, pkg_name

    [type, cat, pkg]
  end

  def category_node(name)
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

  def package_node(cat, name)
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

  def version_node(pkg, name)
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
end

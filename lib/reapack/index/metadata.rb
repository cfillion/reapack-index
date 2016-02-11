class ReaPack::Index
  class Metadata
    TAG = 'metadata'.freeze

    def initialize(parent)
      @parent = parent

      @root = parent.element_children.find {|node| node.name == TAG }
    end

    def modified?
      !!@dirty
    end

    def links(type)
      Link.find_all(type, @root).map {|node| Link.from_node node }
        .select {|link| link.url.index('http') == 0 }
    end

    def push_link(type, name = nil, url)
      Link.check_type type

      unless url =~ /\A#{URI::regexp(['http', 'https'])}\z/
        raise Error, "invalid URL: #{url}"
      end

      make_root

      link = Link.new name || url, url
      node = Link.find type, link.name, @root
      node ||= Link.find type, link.url, @root

      if node
        link.instance_variable_set :@is_new, false
        link.instance_variable_set :@modified, link != Link.from_node(node)

        node.remove_attribute Link::URL
      else
        link.instance_variable_set :@is_new, true
        link.instance_variable_set :@modified, true

        node = Nokogiri::XML::Node.new Link::TAG, @root.document
        node.parent = @root
        node[Link::REL] = type
      end

      if name
        node[Link::URL] = url
        node.content = name
      else
        node.content = url
      end

      @dirty = true

      link
    end

    def remove_link(type, search)
      node = Link.find type, search, @root

      raise Error, "no such #{type} link: #{search}" unless node

      node.remove
      auto_remove

      @dirty = true
    end

  private
    def make_root
      unless @root
        @root = Nokogiri::XML::Node.new TAG, @parent.document
        @root.parent = @parent
      end

      @root
    end

    def auto_remove
      @root.remove if @root.children.empty?
    end
  end

  class Link
    TAG = 'link'.freeze
    REL = 'rel'.freeze
    URL = 'href'.freeze

    # the first type will be the default one
    VALID_TYPES = [:website, :donation].freeze

    def self.from_node(node)
      name, url = node.text.to_s, node[URL].to_s
      url, name = name, url if url.empty?
      name = url if name.empty?

      self.new name, url
    end

    def self.check_type(type)
      raise ArgumentError unless VALID_TYPES.include? type
    end

    def self.same_type?(type, user)
      # match invalid types by the first value of VALID_TYPES
      # while the other values require an exact match
      user == type || (type == VALID_TYPES[0] && VALID_TYPES.index(user).to_i < 1)
    end

    def self.find_all(type, parent)
      Link.check_type type

      return [] unless parent

      parent.element_children.select {|node|
        node.name == TAG && Link.same_type?(type, node[REL].to_s.to_sym)
      }
    end

    def self.find(type, search, parent)
      Link.find_all(type, parent).find {|node|
        node.text == search || node[URL] == search
      }
    end

    def initialize(name, url)
      @name, @url = name, url
      @is_new = @modified = false
    end

    attr_accessor :name, :url

    def ==(other)
      name == other.name && url == other.url
    end

    def is_new?
      @is_new
    end

    def modified?
      @modified
    end
  end
end

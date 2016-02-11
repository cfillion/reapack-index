class ReaPack::Index
  class Metadata
    TAG = 'metadata'.freeze
    LINK = 'link'.freeze
    TYPE = 'rel'.freeze
    URL = 'href'.freeze

    # the first type will be the default one
    VALID_TYPES = [:website, :donation].freeze

    Link = Struct.new :name, :url do
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
          node.name == LINK && Link.same_type?(type, node[TYPE].to_s.to_sym)
        }
      end

      def self.find(type, search, parent)
        Link.find_all(type, parent).find {|node|
          node.text == search || node[URL] == search
        }
      end
    end

    def initialize(parent)
      @parent = parent

      @node = parent.element_children.find {|node| node.name == TAG }
    end

    def modified?
      !!@dirty
    end

    def links(type)
      Link.find_all(type, @node).map {|node|
          name, url = node.text.to_s, node[URL].to_s
          url, name = name, url if url.empty?
          name = url if name.empty?
          Link.new name, url
        }
        .select {|link| link.url.index('http') == 0 }
    end

    def push_link(type, name = nil, url)
      Link.check_type type

      raise Error, "invalid URL: #{url}" unless url.index('http') == 0

      make_node

      link = Link.find type, name || url, @node

      if link
        link.remove_attribute URL
      else
        link = Nokogiri::XML::Node.new LINK, @node.document
        link.parent = @node
        link[TYPE] = type
      end

      if name
        link[URL] = url
        link.content = name
      else
        link.content = url
      end

      @dirty = true
    end

    def remove_link(type, search)
      node = Link.find type, search, @node

      raise Error, "no such #{type} link in this index: #{search}" unless node

      node.remove
      auto_remove

      @dirty = true
    end

  private
    def make_node
      unless @node
        @node = Nokogiri::XML::Node.new TAG, @parent.document
        @node.parent = @parent
      end

      @node
    end

    def auto_remove
      @node.remove if @node.children.empty?
    end
  end
end

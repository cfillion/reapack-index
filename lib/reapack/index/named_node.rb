class ReaPack::Index
  class NamedNode
    NAME_ATTR = 'name'.freeze

    def self.tag;
      raise "@tag is unset" unless @tag
      @tag
    end

    def self.find_in(parent, name)
      node = parent.element_children.find {|node|
        node.name == tag && node[NAME_ATTR] == name
      }

      self.new node if node
    end

    def self.find_all(parent)
      parent.element_children
        .select {|node| node.name == tag }
        .map {|node| self.new node }
    end

    def self.get(name, parent, create)
      return unless parent

      node = self.find_in parent, name

      if create
        node ||= self.new name, parent
      end

      node
    end

    def initialize(node, parent = nil)
      return @node = node if parent.nil?

      @is_new = true
      @dirty = true

      @node = Nokogiri::XML::Node.new self.class.tag, parent.document
      @node[NAME_ATTR] = node
      @node.parent = parent
    end

    attr_reader :node

    def is_new?; !!@is_new; end
    def modified?; !!@dirty; end

    def name
      @node[NAME_ATTR]
    end

    def empty?
      @node.element_children.empty?
    end

    def remove
      @node.remove
    end

    def children(tag)
      @node.element_children.select {|node| node.name == tag }
    end
  end
end

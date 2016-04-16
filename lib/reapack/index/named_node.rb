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

    def self.fetch(name, parent, create)
      return unless parent

      instance = find_in parent, name

      if create
        instance ||= self.create name, parent
      end

      instance
    end

    def self.create(name, parent)
      node = Nokogiri::XML::Node.new tag, parent.document
      node[NAME_ATTR] = name
      node.parent = parent

      instance = new node
      instance.instance_variable_set :@is_new, true
      instance.instance_variable_set :@dirty, true

      instance
    end

    def initialize(node)
      @node = node
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

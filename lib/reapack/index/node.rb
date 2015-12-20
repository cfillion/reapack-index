class ReaPack::Index
  module NamedNode
    as_trait do |tag, attr|
      define_singleton_method :find_in do |parent, name|
        return unless parent

        parent.element_children.select {|node|
          node.name == tag && node[attr] == name
        }.first
      end

      define_method :make_node do |node, parent|
        return [node, false] if parent.nil?

        name, node = node, Nokogiri::XML::Node.new(tag, parent.document)
        node[attr] = name
        node.parent = parent

        [node, parent]
      end
    end
  end
end

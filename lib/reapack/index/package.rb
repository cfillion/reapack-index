class ReaPack::Index
  class Category
    TAG = 'category'.freeze
    NAME = 'name'.freeze

    include NamedNode[TAG, NAME]

    def initialize(node, parent = nil)
      @node, @is_new = make_node node, parent
    end

    attr_reader :node

    def is_new?; @is_new; end

    def empty?
      @node.element_children.empty?
    end

    def remove
      @node.remove
    end
  end

  class Package
    TAG = 'reapack'.freeze
    NAME = 'name'.freeze

    include NamedNode[TAG, NAME]

    def initialize(node, parent = nil)
      @node, @is_new = make_node node, parent
      @versions = {}

      read_versions
    end

    def modified?
      !!@dirty
    end

    def is_new?
      @is_new
    end

    def remove
      @node.remove
    end

    def type
      @node[:type]
    end

    def type=(new_type)
      return if @node[:type].to_s == new_type

      @node[:type] = new_type
      @dirty = true
    end

    def has_version?(name)
      @versions.has_key? name
    end

    def add_version(name)
      ver = @versions[name] = Version.new name, @node
      yield ver
      @dirty ||= ver.modified?
    end

  private
    def read_versions
      @node.element_children.each {|node|
        if node.name == Version::TAG
          @versions[node[:name]] = Version.new node
        end
      }
    end
  end
end

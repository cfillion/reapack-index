class ReaPack::Index
  class Category < NamedNode
    @tag = 'category'.freeze
  end

  class Package < NamedNode
    @tag = 'reapack'.freeze

    TYPE_ATTR = 'type'.freeze

    def initialize(node)
      super
      read_versions
    end

    def modified?
      super || @versions.values.any? {|ver| ver.modified? }
    end

    def category
      @node.parent[NAME_ATTR]
    end

    def path
      @path ||= File.join category, name if category && name
    end

    def type
      @node[TYPE_ATTR]&.to_sym
    end

    def type=(new_type)
      new_type = new_type.to_sym

      return if type == new_type

      @node[TYPE_ATTR] = new_type
      @dirty = true
    end

    def has_version?(name)
      @versions.has_key? name
    end

    def versions
      @versions.values
    end

    def version(name)
      if has_version? name
        ver = @versions[name]
      else
        ver = @versions[name] = Version.create name, @node
      end

      if block_given?
        yield ver
      else
        ver
      end
    end

  private
    def read_versions
      @versions ||= {}

      Version.find_all(@node).each {|ver|
        @versions[ver.name] = ver
      }
    end
  end
end

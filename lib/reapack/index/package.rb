class ReaPack::Index
  class Category < NamedNode
    @tag = 'category'.freeze
  end

  class Package < NamedNode
    @tag = 'reapack'.freeze

    TYPE = 'type'.freeze

    def initialize(node, parent = nil)
      super

      @versions = {}

      read_versions
    end

    def modified?
      super || @versions.values.any? {|ver| ver.modified? }
    end

    def type
      @node[TYPE].to_s
    end

    def type=(new_type)
      new_type ||= String.new

      return if type == new_type

      @node[TYPE] = new_type
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
        ver = @versions[name] = Version.new name, @node
      end

      if block_given?
        yield ver
      else
        ver
      end
    end

  private
    def read_versions
      Version.find_all(@node).each {|ver|
        @versions[ver.name] = ver
      }
    end
  end
end

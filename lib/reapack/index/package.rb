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
      !!@dirty || @versions.values.any? {|ver| ver.modified? }
    end

    def type
      @node[TYPE]
    end

    def type=(new_type)
      return if @node[TYPE].to_s == new_type

      @node[TYPE] = new_type
      @dirty = true
    end

    def has_version?(name)
      @versions.has_key? name
    end

    def version(name)
      if has_version? name
        ver = @versions[name]
      else
        ver = @versions[name] = Version.new name, @node
      end

      yield ver

      @dirty ||= ver.modified?
    end

  private
    def read_versions
      Version.find_all(@node).each {|ver|
        @versions[ver.name] = ver
      }
    end
  end
end

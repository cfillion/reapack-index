class ReaPack::Index
  class ConflictDetector
    Element = Struct.new :key, :platform, :file

    class Selector
      def initialize(key, elements)
        @key, @elements = key, elements
      end

      def push(platform, file)
        @elements << Element.new(@key, platform, file)
      end

      def clear
        @elements.reject! {|e| e.key == @key }
      end
    end

    def initialize
      @elements = []
    end

    def initialize_copy(other)
      super
      other.instance_variable_set :@elements, @elements.dup
    end

    def [](key)
      Selector.new key, @elements
    end

    def conflicts(key = nil)
      dups = @elements.group_by {|e| e.file }.select {|_, a| a.size > 1 }

      errors = dups.map {|f, a|
        packages = a.map {|e| e.key }.uniq
        next if key && !packages.include?(key)

        if packages.size == 1 || !key
          original = sort(a)[1]
          msg = "duplicate file '#{original.file}'"
        else
          original = sort(a.select {|e| e.key != key }).first
          msg = "'#{original.file}' conflicts with '#{original.key}'"
        end

        platforms = a.map {|e| e.platform }.uniq

        if platforms.size > 1
          # check platform inheritance
          platforms.any? {|p|
            loop do
              p = Source::PLATFORMS[p] or break false
              break true if platforms.include? p
            end
          } or next
        end

        platform = original.platform
        platform == :all ? msg : "#{msg} on #{platform}"
      }.compact

      errors unless errors.empty?
    end

  private
    def sort(set)
      sorted = set.sort_by {|e| levels[e.platform] }
      sorted.sort_by! {|e| Source::PLATFORMS.keys.index e.platform }
    end

    def levels
      @@levels ||= begin
        Hash[Source::PLATFORMS.map {|name, parent|
          levels = 0

          loop do
            break unless parent
            levels += 1
            parent = Source::PLATFORMS[parent]
          end

          [name, levels]
        }]
      end
    end
  end
end

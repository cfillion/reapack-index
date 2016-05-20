class ReaPack::Index
  class ConflictDetector
    Entry = Struct.new :key, :platform, :file

    class Selector
      def initialize(key, cdetector)
        @key, @cdetector = key, cdetector
      end

      def push(bucket, platform, file)
        @cdetector.bucket(bucket) << Entry.new(@key, platform, file).freeze
      end

      def clear
        @cdetector.buckets.each_value do |b|
          b.reject! {|e| e.key == @key }
        end
      end

      def resolve
        errors = @cdetector.buckets.map do |b, _|
          @cdetector.resolve b, @key
        end.compact.flatten

        errors unless errors.empty?
      end
    end

    def initialize
      @buckets = {}
    end

    def initialize_clone(other)
      super
      other.instance_variable_set :@buckets,
        Hash[@buckets.map {|k, v| [k, v.clone] }]
    end

    def [](key)
      Selector.new key, self
    end

    attr_reader :buckets

    def bucket(name)
      raise ArgumentError, 'bucket name is not a symbol' unless name.is_a? Symbol
      @buckets[name] ||= []
    end

    def clear
      @buckets.clear
    end

    def resolve(bname, key = nil)
      dups = bucket(bname).group_by {|e| e.file }.values.select {|a| a.size > 1 }

      errors = dups.map {|a|
        packages = a.map {|e| e.key }.uniq
        next if key && !packages.include?(key)

        if packages.size == 1 || !key
          original = sort_platforms(a)[1]
          msg = "duplicate file '#{original.file}'"
        else
          original = sort_platforms(a.select {|e| e.key != key }).first
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

    def load_xml(node)
      Category.find_all(node).each {|cat|
        Package.find_all(cat.node).each {|pkg|
          pkgroot = File.join(cat.name, pkg.name)

          pkg.versions.last&.children(Source::TAG)&.each {|src|
            type = src[:type] || pkg.type
            platform = src[:platform] || :all
            entry = Entry.new pkgroot, platform.to_sym

            if src[:file]
              entry.file = ReaPack::Index.expand(src[:file], cat.name)
            else
              entry.file = pkgroot
            end

            bucket(type.to_sym) << entry
          }
        }
      }
    end

  private
    def sort_platforms(set)
      set.group_by {|e| levels[e.platform] || 0 }.sort
        .map {|_, a| a.sort_by {|e| Source::PLATFORMS.keys.index(e.platform) || 0 } }
        .flatten
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

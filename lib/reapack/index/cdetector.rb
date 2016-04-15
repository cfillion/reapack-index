class ReaPack::Index
  class ConflictDetector
    Entry = Struct.new :key, :platform, :file

    class Selector
      def initialize(bucket, key, cdetector)
        @bucket, @key, @cdetector = bucket, key, cdetector
        @entries = @cdetector.bucket bucket
      end

      def push(platform, file)
        @entries << Entry.new(@key, platform, file).freeze
      end

      def clear
        @entries.reject! {|e| e.key == @key }
      end

      def resolve
        @cdetector.resolve @bucket, @key
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

    def [](bucket, key)
      Selector.new bucket, key, self
    end

    def bucket(name)
      @buckets[name] ||= []
    end

    def resolve(bucket, key = nil)
      return unless bucket = @buckets[bucket]

      dups = bucket.group_by {|e| e.file }.values.select {|a| a.size > 1 }

      errors = dups.map {|a|
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

    def load_xml(node)
      Category.find_all(node).each {|cat|
        Package.find_all(cat.node).each {|pkg|
          pkgroot = File.join(cat.name, pkg.name)

          pkg.versions.last&.children(Source::TAG)&.each {|src|
            entry = Entry.new pkgroot, src[:platform].to_sym

            if src[:file]
              entry.file = ReaPack::Index.expand(src[:file], cat.name)
            else
              entry.file = pkgroot
            end

            bucket(pkg.type) << entry
          }
        }
      }
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

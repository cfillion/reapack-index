class ReaPack::Index
  class Source
    TAG = 'source'.freeze
    PLATFORM = 'platform'.freeze
    FILE = 'file'.freeze

    PLATFORMS = {
      all: nil,
      windows: :all, win32: :windows, win64: :windows,
      darwin: :all, darwin32: :darwin, darwin64: :darwin,
    }.freeze

    def self.validate_platform(platform)
      return unless platform # nil platform will be replaced by the default

      unless PLATFORMS.has_key? platform.to_sym
        raise Error, "invalid platform '#{platform}'"
      end
    end

    def initialize(platform = nil, file = nil, url = nil)
      self.platform = platform
      self.file = file
      self.url = url
    end

    def platform=(new_platform)
      new_platform ||= :all
      new_platform = new_platform.to_sym

      self.class.validate_platform new_platform

      @platform = new_platform
    end

    attr_reader :platform
    attr_accessor :file, :url

    def make_node(parent)
      @node = Nokogiri::XML::Node.new TAG, parent.document
      @node[PLATFORM] = @platform
      @node[FILE] = @file if @file
      @node.content = Addressable::URI.encode @url
      @node.parent = parent
    rescue Addressable::URI::InvalidURIError => e
      raise Error, e.message
    end
  end

  class SourceCollection
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

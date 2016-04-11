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

      unless PLATFORMS.has_key? platform
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

    def initialize
      @elements = []
    end

    def push(key, source)
      @elements << Element.new(key, source.platform, source.file)
    end

    def <<(source)
      push nil, source
    end

    def conflicts(key = false)
      dups = @elements.group_by {|e| e.file }.select {|_, a| a.size > 1 }

      errors = dups.map {|f, a|
        packages = a.map {|e| e.key }.uniq
        next unless key == false || packages.include?(key)

        if key == false || packages.size == 1
          original = sort(a, &:last)
          msg = "duplicate file '#{original.file}'"
        else
          original = sort(a.select {|e| e.key != key }, &:first)
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
      grouped = set.group_by {|e| levels[e.platform] }
      level = yield grouped.keys.sort

      grouped[level]
        .sort_by {|e| Source::PLATFORMS.keys.index e.platform }
        .first
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

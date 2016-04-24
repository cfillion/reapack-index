class ReaPack::Index
  class Source
    TAG = 'source'.freeze
    PLATFORM = 'platform'.freeze
    TYPE = 'type'.freeze
    FILE = 'file'.freeze

    PLATFORMS = {
      all: nil,
      windows: :all, win32: :windows, win64: :windows,
      darwin: :all, darwin32: :darwin, darwin64: :darwin,
    }.freeze

    class << self
      def is_platform?(input)
        PLATFORMS.has_key? input&.to_sym
      end
    end

    def initialize(url = nil)
      @url = url
      @platform = :all
    end

    attr_reader :platform, :type
    attr_accessor :file, :url

    def platform=(new_platform)
      new_platform ||= :all

      unless self.class.is_platform? new_platform
        raise Error, "invalid platform '#{new_platform}'"
      end

      @platform = new_platform.to_sym
    end

    def type=(new_type)
      return @type = new_type if new_type.nil?

      unless ReaPack::Index.is_type? new_type
        raise Error, "invalid type '#{new_type}'"
      end

      @type = new_type.to_sym
    end

    def make_node(parent)
      @node = Nokogiri::XML::Node.new TAG, parent.document
      @node[PLATFORM] = @platform
      @node[TYPE] = @type if @type
      @node[FILE] = @file if @file
      @node.content = Addressable::URI.parse(@url).normalize.to_s
      @node.parent = parent
    rescue Addressable::URI::InvalidURIError => e
      raise Error, e.message
    end
  end
end

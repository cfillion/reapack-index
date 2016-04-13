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
end

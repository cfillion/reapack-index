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
    Element = Struct.new :id, :source

    def initialize
      @elements = []
    end

    def push(source, id = nil)
      @elements << Element.new(id, source)
    end

    alias :<< :push

    def conflicts
      dups = @elements.group_by {|e| e.source.file }.select {|_, a| a.size > 1 }

      errors = dups.map {|f, a|
        msg = "duplicate file '#{a.first.source.file}'"

        a.group_by {|e| e.id }.map {
          platforms = a.group_by {|e| e.source.platform }.keys

          if platforms.size > 1
            platform = platforms.find {|p|
              # if this file is also available for the parent platform
              platforms.include? ReaPack::Index::Source::PLATFORMS[p]
            } or next
          else
            platform = platforms.first
          end

          platform == :all ? msg : "#{msg} on #{platform}"
        }
      }.flatten.compact

      errors unless errors.empty?
    end
  end
end

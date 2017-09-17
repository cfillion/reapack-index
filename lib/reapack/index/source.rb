class ReaPack::Index
  class Source
    TAG = 'source'.freeze
    PLATFORM = 'platform'.freeze
    TYPE = 'type'.freeze
    FILE = 'file'.freeze
    MAIN = 'main'.freeze

    PLATFORMS = {
      all: nil,
      windows: :all, win32: :windows, win64: :windows,
      darwin: :all, darwin32: :darwin, darwin64: :darwin,
      linux: :all, linux32: :linux, linux64: :linux,
    }.freeze

    SECTIONS = [
      :main, :midi_editor, :midi_inlineeditor, :midi_eventlisteditor,
      :mediaexplorer
    ].freeze

    class << self
      def is_platform?(input)
        PLATFORMS.has_key? input&.to_sym
      end
    end

    def initialize(url)
      @url = url
      @sections = []
      @platform = :all
    end

    attr_reader :platform, :type, :sections
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

    def detect_sections(pkg)
      @sections = []

      if (@type || pkg.type) == :script
        @sections <<
          case pkg.topdir.downcase
          when 'midi editor'
            :midi_editor
          when 'midi inline editor'
            :midi_inlineeditor
          when 'midi event list editor'
            :midi_eventlisteditor
          when 'media explorer'
            :mediaexplorer
          else
            :main
          end
      end

      @sections.freeze # force going through sections=() for validation
    end

    def sections=(new_sections)
      new_sections.each {|s|
        unless SECTIONS.include? s
          raise Error, "invalid Action List section '#{s}'"
        end
      }

      @sections = new_sections.sort {|s| SECTIONS.index s }.freeze
    end

    def make_node(parent)
      @node = Nokogiri::XML::Node.new TAG, parent.document
      @node[MAIN] = @sections.join "\x20" unless @sections.empty?
      @node[PLATFORM] = @platform if @platform != :all
      @node[TYPE] = @type if @type
      @node[FILE] = @file if @file
      @node.content = Addressable::URI.parse(@url).normalize.to_s
      @node.parent = parent
    rescue Addressable::URI::InvalidURIError => e
      raise Error, e.message
    end
  end
end

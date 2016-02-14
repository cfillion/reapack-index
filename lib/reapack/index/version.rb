class ReaPack::Index
  class Version < NamedNode
    @tag = 'version'.freeze

    AUTHOR = 'author'.freeze
    TIME = 'time'.freeze

    def initialize(node, parent = nil)
      super

      @changelog = Changelog.new @node
    end

    def modified?
      super || @changelog.modified?
    end

    def changelog=(new_text)
      @changelog.text = new_text
    end

    def author
      @node[AUTHOR].to_s
    end

    def author=(new_author)
      new_author ||= String.new

      return if author == new_author

      if new_author.empty?
        @node.remove_attribute AUTHOR
      else
        @node[AUTHOR] = new_author
      end

      @dirty = true
    end

    def time
      Time.parse @node[TIME] if @node.has_attribute? TIME
    end

    def time=(new_time)
      return if new_time == time

      if new_time.nil?
        @node.remove_attribute TIME
      else
        @node[TIME] = new_time.utc.iso8601
      end

      @dirty = true
    end

    def replace_sources
      was_dirty = @dirty

      old_sources = hash_sources children(Source::TAG)
        .each {|node| node.remove }

      yield

      new_sources = hash_sources children(Source::TAG)
      @dirty = was_dirty || old_sources != new_sources

      if new_sources.empty?
        raise Error, 'no sources found. @provides tag missing?'
      end
    end

    def add_source(src, file = nil, url = nil)
      src = Source.new src, file, url unless src.is_a? Source
      src.make_node @node

      @dirty = true
    end

  private
    def hash_sources(nodes)
      nodes.map {|src|
        [src[Source::PLATFORM], src[Source::FILE], src.content]
      }
    end
  end

  class Source
    TAG = 'source'.freeze
    PLATFORM = 'platform'.freeze
    FILE = 'file'.freeze

    PLATFORMS = [
      :all,
      :windows, :win32, :win64,
      :darwin, :darwin32, :darwin64,
    ].freeze


    def initialize(platform = nil, file = nil, url = nil)
      self.platform = platform
      self.file = file
      self.url = url
    end

    def platform=(new_platform)
      new_platform = :all if new_platform.nil?

      unless PLATFORMS.include? new_platform.to_sym
        raise Error, 'invalid platform: %s' % new_platform
      end

      @platform = new_platform
    end

    attr_reader :platform
    attr_accessor :file, :url

    def make_node(parent)
      @node = Nokogiri::XML::Node.new TAG, parent.document
      @node.parent = parent
      @node[PLATFORM] = @platform
      @node[FILE] = @file if @file
      @node.content = URI.escape @url
    end
  end

  class Changelog
    TAG = 'changelog'.freeze

    def initialize(parent)
      @parent = parent

      @node = parent.element_children.find {|node| node.name == TAG }

      if @node
        cdata = @node.children.first
        @text = cdata.content
      else
        @text = String.new
      end
    end

    def modified?
      !!@dirty
    end

    attr_reader :text

    def text=(new_text)
      new_text ||= String.new

      if text == new_text
        return
      else
        @dirty = true
      end

      return @node.remove if new_text.empty?

      if @node
        @node.children.each {|n| n.remove }
      else
        @node = Nokogiri::XML::Node.new TAG, @parent.document
        @node.parent = @parent
      end

      cdata = Nokogiri::XML::CDATA.new @node.document, new_text
      cdata.parent = @node

      @text = new_text
    end
  end
end

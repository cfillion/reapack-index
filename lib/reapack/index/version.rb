class ReaPack::Index
  class Version < NamedNode
    @tag = 'version'.freeze

    def initialize(node, parent = nil)
      super

      @changelog = Changelog.new @node
    end

    def modified?
      !!@dirty
    end

    def changelog=(new_text)
      return if new_text == @changelog.text

      @changelog.text = new_text
      @dirty = true
    end

    def change_sources
      old_sources = hash_sources children(Source::TAG)
        .each {|node| node.remove }

      yield

      new_sources = hash_sources children(Source::TAG)
      @dirty ||= old_sources != new_sources
    end

    def add_source(platform, file, url)
      src = Source.new @node
      src.platform = platform
      src.file = file
      src.url = url
    end

  private
    def hash_sources(sources)
      sources.map {|src|
        [src[Source::PLATFORM], src[Source::FILE], src.content]
      }
    end
  end

  class Source
    TAG = 'source'.freeze
    PLATFORM = 'platform'.freeze
    FILE = 'file'.freeze

    def initialize(parent)
      @node = Nokogiri::XML::Node.new TAG, parent.document
      @node.parent = parent
    end

    def platform=(new_platform)
      @node[PLATFORM] = new_platform
    end

    def file=(new_file)
      @node[FILE] = new_file if new_file
    end

    def url=(new_url)
      @node.content = URI.escape new_url
    end
  end

  class Changelog
    TAG = 'changelog'.freeze

    def initialize(parent)
      @parent = parent

      @node = parent.element_children.select {|node|
        node.name == TAG
      }.first

      if @node
        cdata = @node.children.first
        @text = cdata.content
      else
        @text = String.new
      end
    end

    attr_reader :text

    def text=(new_text)
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

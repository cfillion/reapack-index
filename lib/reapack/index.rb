require 'reapack/index/version'

require 'nokogiri'

class ReaPack::Index
  attr_reader :path

  def initialize path
    @path = path

    if File.exists? path
      @doc = File.open(path) {|f| Nokogiri::XML(f) }
    else
      @doc = Nokogiri::XML::Document.new
      @doc.root = Nokogiri::XML::Node.new 'index', @doc
      self.version = 1
    end
  end

  def version
    @doc.root[:version].to_i
  end

  def version=(ver)
    @doc.root[:version] = ver
  end

  def commit
    @doc.root[:commit]
  end

  def commit=(sha1)
    @doc.root[:commit] = sha1
  end

  def write(path)
    File.write path, @doc.to_xml
  end

  def write!
    write @path
  end
end

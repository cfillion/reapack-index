require 'reapack/index/gem_version'

require 'git'
require 'io/console'
require 'metaheader'
require 'modularity'
require 'nokogiri'
require 'optparse'
require 'uri'

require 'reapack/index/git_patch'
require 'reapack/index/indexer'
require 'reapack/index/node'
require 'reapack/index/package'
require 'reapack/index/version'

class ReaPack::Index
  Error = Class.new RuntimeError

  FILE_TYPES = {
    'lua' => :script,
    'eel' => :script,
  }.freeze

  HEADER_RULES = {
    :version => /\A(?:[^\d]*\d{1,4}[^\d]*){1,4}\z/,
    :changelog => [MetaHeader::OPTIONAL, /.+/],
  }.freeze

  SOURCE_HOSTS = {
    /\Agit@github\.com:([^\/]+)\/(.+)\.git\z/ =>
      'https://github.com/\1/\2/raw/$commit/$path',
    /\Ahttps:\/\/github\.com\/([^\/]+)\/(.+)\.git\z/ =>
      'https://github.com/\1/\2/raw/$commit/$path',
  }.freeze


  attr_reader :path, :source_pattern
  attr_accessor :pwd

  def self.type_of(path)
    ext = File.extname(path)[1..-1]
    FILE_TYPES[ext]
  end

  def self.source_for(url)
    SOURCE_HOSTS.each_pair {|regex, pattern|
      return url.gsub regex, pattern if url =~ regex
    }

    nil
  end

  def self.validate_file(path)
    mh = MetaHeader.from_file path
    return if mh[:noindex]

    mh.validate HEADER_RULES
  end

  def initialize(path)
    @path = path
    @changes = {}
    @pwd = String.new
    @is_file = Proc.new {|path| File.file? File.join(@pwd, path) }

    if File.exists? path
      @dirty = false

      @doc = Nokogiri::XML File.open(path) do |config|
        # don't add extra blank lines
        # because they don't go away when we remove a node
        config.noblanks
      end
    else
      @dirty = true

      @doc = Nokogiri::XML::Document.new
      @doc.root = Nokogiri::XML::Node.new 'index', @doc
      self.version = 1
    end

    @doc.encoding = 'utf-8'
  end

  def scan(path, contents, &block)
    type = self.class.type_of path
    return unless type

    mh = MetaHeader.new contents

    if mh[:noindex]
      remove path
      return
    end

    if errors = mh.validate(HEADER_RULES)
      raise Error, "Invalid metadata in #{path}:\n#{errors.inspect}"
    end

    cat, pkg = find path

    log_change 'new category', 'new categories' if cat.is_new?
    log_change 'new package' if pkg.is_new?

    pkg.type = type.to_s

    basepath = dirname path
    deps = filelist mh[:provides].to_s, basepath

    unless pkg.has_version? mh[:version]
      log_change 'new version'

      pkg.add_version mh[:version] do |ver|
        ver.changelog = mh[:changelog].to_s

        ver.change_sources do
          ver.add_source :all, nil, url_for(path, &block)

          deps.each_pair {|file, path|
            ver.add_source :all, file, url_for(path, &block)
          }
        end
      end
    end

    log_change 'updated package' if pkg.modified? && !pkg.is_new?
  end
  
  def remove(path)
    cat, pkg = find path, false
    return unless pkg

    pkg.remove
    cat.remove if cat.empty?

    log_change "removed #{pkg.type}"
  end

  def source_pattern=(pattern)
    return if pattern.nil?
    raise ArgumentError, '$path not in pattern' unless pattern.include? '$path'

    @source_pattern = pattern
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

    @dirty = false
    @changes.clear
  end

  def modified?
    @dirty
  end

  def changelog
    list = []

    @changes.each_pair {|type, data|
      count, plural = data
      list << "#{count} #{count != 1 ? plural : type}"
    }

    list.empty? ? nil : list.join(', ')
  end

private
  def log_change(desc, plural = nil)
    @dirty = true

    @changes[desc] ||= [0, plural || desc + 's']
    @changes[desc][0] += 1
  end

  def dirname(path)
    name = File.dirname path
    name == '.' ? nil : name
  end

  def find(path, create = true)
    cat_name = dirname(path) || 'Other'
    pkg_name = File.basename path

    cat = auto_create Category, cat_name, @doc.root, create
    pkg = auto_create Package, pkg_name, cat && cat.node, create

    [cat, pkg]
  end

  def auto_create(klass, name, parent, create)
    return unless parent

    node = klass.find_in parent, name

    if node
      klass.new node
    elsif create
      klass.new name, parent
    end
  end

  def url_for(path, &block)
    block ||= @is_file

    unless @source_pattern
      raise Error, "Source pattern is unset " \
        "and the package doesn't specify its source url"
    end

    unless block[path.to_s]
      raise Error, "#{path}: No such file or directory"
    end

    @source_pattern
      .sub('$path', path)
      .sub('$commit', commit || 'master')
  end

  def filelist(list, base)
    deps = list.lines.map {|line|
      line.chomp!
      path = base ? File.join(base, line) : line

      [line, path]
    }

    Hash[*deps.flatten]
  end
end

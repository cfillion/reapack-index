require 'reapack/index/gem_version'

require 'colorize'
require 'fileutils'
require 'io/console'
require 'metaheader'
require 'nokogiri'
require 'optparse'
require 'pathname'
require 'rugged'
require 'shellwords'
require 'uri'

require 'reapack/index/indexer'
require 'reapack/index/named_node'
require 'reapack/index/package'
require 'reapack/index/parsers'
require 'reapack/index/version'

class ReaPack::Index
  Error = Class.new RuntimeError

  FILE_TYPES = {
    'lua' => :script,
    'eel' => :script,
  }.freeze

  HEADER_RULES = {
    # package-wide tags
    :version => /\A(?:[^\d]*\d{1,4}[^\d]*){1,4}\z/,

    # version-specific tags
    :author => [MetaHeader::OPTIONAL, /\A[^\n]+\z/],
    :changelog => [MetaHeader::OPTIONAL, /.+/],
    :provides => [MetaHeader::OPTIONAL, Proc.new {|value|
      files = value.lines.map {|l| l.chomp }
      dup = files.detect {|f| files.count(f) > 1 }
      "duplicate file (%s)" % dup if dup
    }]
  }.freeze

  SOURCE_HOSTS = {
    /\Agit@github\.com:([^\/]+)\/(.+)\.git\z/ =>
      'https://github.com/\1/\2/raw/$commit/$path',
    /\Ahttps:\/\/github\.com\/([^\/]+)\/(.+)\.git\z/ =>
      'https://github.com/\1/\2/raw/$commit/$path',
  }.freeze

  ROOT = File.expand_path('/').freeze

  attr_reader :path, :source_pattern
  attr_accessor :amend, :files

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
    @amend = false
    @changes = {}
    @files = []
    @path = path

    if File.exist? path
      # noblanks: don't preserve the original white spaces
      # so we always output a neat document
      setup = proc {|config| config.noblanks }
      @doc = Nokogiri::XML File.open(path), &setup
    else
      @dirty = true
      @is_new = true

      @doc = Nokogiri::XML::Document.new
      @doc.root = Nokogiri::XML::Node.new 'index', @doc
    end

    @doc.root[:version] = 1
    @doc.encoding = 'utf-8'
  end

  def scan(path, contents)
    type = self.class.type_of path
    return unless type

    mh = MetaHeader.new contents

    backup = @doc.root.dup

    if mh[:noindex]
      remove path
      return
    end

    if errors = mh.validate(HEADER_RULES)
      prefix = "\n\x20\x20"
      raise Error, "Invalid metadata in %s:%s" %
        [path, prefix + errors.join(prefix)]
    end

    basepath = dirname path
    deps = filelist mh[:provides].to_s, basepath

    cat, pkg = find path
    pkg.type = type.to_s

    pkg.version mh[:version] do |ver|
      next unless ver.is_new? || @amend

      ver.author = mh[:author]
      ver.changelog = mh[:changelog]

      ver.replace_sources do
        ver.add_source :all, nil, url_for(path)

        deps.each_pair {|filename, dep_path|
          ver.add_source :all, filename, url_for(dep_path)
        }
      end
    end

    log_change 'new category', 'new categories' if cat.is_new?

    if pkg.is_new?
      log_change 'new package'
    elsif pkg.modified?
      log_change 'modified package'
    end

    pkg.versions.each {|ver|
      if ver.is_new?
        log_change 'new version'
      elsif ver.modified?
        log_change 'modified version'
      end
    }
  rescue Error
    @doc.root = backup
    raise
  end
  
  def remove(path)
    cat, pkg = find path, false
    return unless pkg

    pkg.remove
    cat.remove if cat.empty?

    log_change 'removed package'
  end

  def source_pattern=(pattern)
    if pattern.nil?
      raise ArgumentError, 'Cannot use nil as a source pattern'
    elsif not pattern.include? '$path'
      raise ArgumentError, '$path not in source pattern'
    end

    @source_pattern = pattern
  end

  def version
    @doc.root[:version].to_i
  end

  def commit
    @doc.root[:commit]
  end

  def commit=(sha1)
    if sha1.nil?
      @doc.root.remove_attribute 'commit'
    else
      @doc.root['commit'] = sha1
    end
  end

  def write(path)
    FileUtils.mkdir_p File.dirname(path)
    File.write path, @doc.to_xml
  end

  def write!
    write @path

    @is_new = @dirty = false
    @changes.clear
  end

  def modified?
    !!@dirty
  end

  def changelog
    list = []

    @changes.each_pair {|type, data|
      count, plural = data
      list << "#{count} #{count != 1 ? plural : type}"
    }

    if list.empty?
      @is_new ? 'empty index' : nil
    else
      list.join(', ')
    end
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

    cat = Category.get cat_name, @doc.root, create
    pkg = Package.get pkg_name, cat && cat.node, create

    [cat, pkg]
  end

  def url_for(path)
    unless @source_pattern
      raise Error, "Source pattern is unset " \
        "and the package doesn't specify its source url"
    end

    unless @files.include? path
      raise Error, "#{path}: No such file or directory"
    end

    @source_pattern
      .sub('$path', path)
      .sub('$commit', commit || 'master')
  end

  def filelist(list, base)
    deps = list.lines.map {|line|
      line.chomp!
      path = File.expand_path line, ROOT + base

      [line, path[ROOT.size..-1]]
    }

    Hash[*deps.flatten]
  end
end

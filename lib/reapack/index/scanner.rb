class ReaPack::Index
  class Scanner
    PROVIDES_VALIDATOR = proc {|value|
      begin
        Provides.parse_each(value).to_a and nil
      rescue Error => e
        e.message
      end
    }

    VERSION_SEGMENT_MAX = (2 ** 16) - 1

    SIMPLE_TAG = [MetaHeader::VALUE, MetaHeader::SINGLELINE].freeze

    HEADER_RULES = {
      # package-wide tags
      version: [
        MetaHeader::REQUIRED, MetaHeader::VALUE, MetaHeader::SINGLELINE, /\A\d/,
        proc {|v|
          s = v.scan(/\d+/).find {|s| s.to_i > VERSION_SEGMENT_MAX }
          'segment overflow (%d > %d)' % [s, VERSION_SEGMENT_MAX] if s
        }
      ],
      about: MetaHeader::VALUE,
      description: SIMPLE_TAG,
      donation: MetaHeader::VALUE,
      link: MetaHeader::VALUE,
      noindex: MetaHeader::BOOLEAN,
      screenshot: MetaHeader::VALUE,

      # version-specific tags
      author: SIMPLE_TAG,
      changelog: MetaHeader::VALUE,
      metapackage: MetaHeader::BOOLEAN,
      provides: [MetaHeader::VALUE, PROVIDES_VALIDATOR],
    }.freeze

    HEADER_ALIASES = {
      [:reascript_name, :jsfx_name, :theme_name,
        :extension_name, :langpack_name, :webinterface_name,
        :desc, :name] => :description,
      [:links, :website] => :link,
      :donate => :donation,
      :screenshots => :screenshot,
    }.freeze

    META_TYPES = [:extension, :data, :theme, :webinterface].freeze

    def initialize(cat, pkg, mh, index)
      @cat, @pkg, @mh, @index = cat, pkg, mh, index
      @cselector = @index.cdetector[pkg.path]
      @self_overriden = false
    end

    def run
      @mh.alias HEADER_ALIASES

      if errors = @mh.validate(HEADER_RULES)
        raise Error, errors.join("\n")
      end

      @pkg.description = @mh[:description]
      @pkg.metadata.about = @mh[:about]

      eval_links :website, tag: :link
      eval_links :screenshot
      eval_links :donation

      @pkg.version @mh[:version] do |ver|
        next unless ver.is_new? || @index.amend

        @ver = ver

        ver.author = @mh[:author]
        ver.time = @index.time if @index.time && ver.is_new?
        ver.changelog = @mh[:changelog]

        ver.replace_sources do
          @cselector.clear
          sources = parse_provides @mh[:provides]

          unless metapackage? || @self_overriden
            # add the package itself as a main source
            src = Source.new make_url(@pkg.path)
            src.detect_sections @pkg
            sources.unshift src

            @cselector.push @pkg.type, src.platform, @pkg.path
          end

          sources.each {|src| ver.add_source src }
        end
      end

      if cons = @cselector.resolve
        raise Error, cons.first unless cons.empty?
      end
    end

    def make_url(path, template = nil)
      unless template
        unless template = @index.url_template
          raise Error, 'unable to generate download links: empty url template'
        end

        unless @index.files.include? path
          raise Error, "file not found '#{path}'"
        end
      end

      template
        .gsub('$path', URI::encode(path))
        .gsub('$commit', @index.commit || 'master')
        .gsub('$version', @ver.name)
        .gsub('$package', @pkg.path)
    end

    def parse_provides(provides)
      pathdir = Pathname.new @pkg.category

      Provides.parse_each(provides).map {|line|
        line.file_pattern = @pkg.name if line.file_pattern == '.'

        expanded = ReaPack::Index.expand line.file_pattern, @pkg.category

        if expanded == @pkg.path
          # always resolve path even when an url template is set
          files = [expanded]
        elsif line.url_template.nil?
          files = @index.files.select {|f|
            File.fnmatch expanded, f, File::FNM_PATHNAME | File::FNM_EXTGLOB
          }
          raise Error, "file not found '#{line.file_pattern}'" if files.empty?
        else
          # use the relative path for external urls
          if line.file_pattern.start_with? '/'
            prefix = []
            dirs = File.split(@pkg.category).size - 1
            dirs.times { prefix << '..' }

            files = [File.join(*prefix, line.file_pattern)]
          else
            files = [line.file_pattern]
          end
        end

        files.map {|file|
          if line.target
            if line.target =~ /[\/\\\.]+\z/
              new_dir = ReaPack::Index.expand line.target, ''
              base_file = File.basename file
              target = new_dir.empty? ? base_file : File.join(new_dir, base_file)
            else
              target = line.target
            end

            expanded = ReaPack::Index.expand target, @pkg.category
          else
            target = file
          end

          src = Source.new make_url(file, line.url_template)
          src.platform = line.platform
          src.type = line.type

          case line.main?
          when true
            src.detect_sections @pkg
          when Array
            src.sections = line.main?
          end

          @cselector.push src.type || @pkg.type, src.platform,
            line.url_template || line.target ? expanded : target

          if file == @pkg.path
            if metapackage?
              # the current file is still added as a source even if @metapackage
              # is enabled but won't be added to the Action List unless specified
            elsif line.main.nil?
              # not a metapackage? then the current file is registered by default
              src.detect_sections @pkg
            end

            src.file = target if line.target && expanded != file
            @self_overriden = true
          else
            if line.url_template
              src.file = file
            elsif line.target
              src.file = target
            else
              src.file = Pathname.new(file).relative_path_from(pathdir).to_s
            end
          end

          src
        }
      }.flatten
    end

    def eval_links(type, tag: nil)
      tag ||= type

      @pkg.metadata.replace_links type do
        @mh[tag].to_s.each_line {|line|
          line.strip!
          @pkg.metadata.push_link type, *Link.split(line) unless line.empty?
        }
      end
    end

    def metapackage?
      @metapackage ||= if @mh[:metapackage].nil?
        META_TYPES.include? @pkg.type
      else
        @mh[:metapackage]
      end
    end
  end
end

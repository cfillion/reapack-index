class ReaPack::Index
  class Scanner
    PROVIDES_VALIDATOR = proc {|value|
      begin
        Provides.parse_each(value).to_a and nil
      rescue Error => e
        e.message
      end
    }

    HEADER_RULES = {
      # package-wide tags
      :version => [
        MetaHeader::REQUIRED, MetaHeader::VALUE, MetaHeader::SINGLELINE, /\d/],

      # version-specific tags
      :author => [MetaHeader::VALUE, MetaHeader::SINGLELINE],
      :changelog => [MetaHeader::VALUE],
      :provides => [MetaHeader::VALUE, PROVIDES_VALIDATOR],
      :index => [MetaHeader::BOOLEAN],
      :main => [MetaHeader::BOOLEAN],
    }.freeze

    WITH_MAIN = [:script, :effect].freeze

    def initialize(cat, pkg, mh, index)
      @cat, @pkg, @mh, @index = cat, pkg, mh, index
      @is_main = !@mh[:metapackage] && WITH_MAIN.include?(pkg.type)
      @cselector = @index.cdetector[pkg.path]
    end

    def run
      if errors = @mh.validate(HEADER_RULES)
        raise Error, errors.join("\n")
      end

      @pkg.version @mh[:version] do |ver|
        next unless ver.is_new? || @index.amend

        @ver = ver

        ver.author = @mh[:author]
        ver.time = @index.time if @index.time && ver.is_new?
        ver.changelog = @mh[:changelog]

        ver.replace_sources do
          @cselector.clear
          sources = parse_provides @mh[:provides]

          if @is_main && sources.none? {|src| src.file.nil? }
            # add the package itself as a main source
            src = Source.new make_url(@pkg.path), @mh[:main, true]
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
        .gsub('$path', path)
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
          files = [line.file_pattern]
        end

        files.map {|file|
          src = Source.new make_url(file, line.url_template), line.main?
          src.platform = line.platform
          src.type = line.type

          @cselector.push src.type || @pkg.type, src.platform,
            line.url_template ? expanded : file

          if file == @pkg.path
            src.main = @is_main if line.main.nil?
          else
            if line.url_template
              src.file = file
            else
              src.file = Pathname.new(file).relative_path_from(pathdir).to_s
            end
          end

          src
        }
      }.flatten
    end
  end
end

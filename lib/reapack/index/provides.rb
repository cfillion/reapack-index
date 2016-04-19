class ReaPack::Index
  Provides = Struct.new :file_pattern, :url_template, :platform, :type do
    PROVIDES_REGEX = /
      \A
      ( \[ \s* (?<options> .+? ) \s* \] )?
      \s*
      (?<file> .+?)
      ( \s+ (?<url> (?:file|https?):\/\/.+ ) )?
      \z
    /x.freeze

    class << self
      def parse_each(input)
        if block_given?
          input.to_s.lines.map {|line| yield parse(line) }
        else
          enum_for :parse_each, input
        end
      end

      def parse(line)
        m = line.strip.match PROVIDES_REGEX
        options, pattern, url_tpl = m[:options], m[:file], m[:url]

        instance = self.new pattern, url_tpl

        options and options.split(',').each {|user_opt|
          opt = user_opt.strip.downcase.to_sym
          next if opt.empty?

          if Source.is_platform? opt
            instance.platform = opt
          elsif type = ReaPack::Index.resolve_type(opt)
            instance.type = type
          else
            raise Error, "unknown option (platform or type) '#{user_opt}'"
          end
        }

        instance
      end
    end
  end
end

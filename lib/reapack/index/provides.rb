class ReaPack::Index
  Provides = Struct.new :file_pattern, :url_template, :platform, :type, :main do
    PROVIDES_REGEX = /
      \A
      ( \[ \s* (?<options> .+? ) \s* \] )?
      \s*
      (?<file> .+?)
      ( \s+ (?<url> (?:file|https?):\/\/.+ ) )?
      \z
    /x.freeze

    alias :main? :main

    class << self
      def parse_each(input)
        if block_given?
          input.to_s.lines.map {|line| i = parse(line) and yield i }
        else
          enum_for :parse_each, input
        end
      end

      def parse(line)
        m = line.strip.match PROVIDES_REGEX
        return unless m

        options, pattern, url_tpl = m[:options], m[:file], m[:url]

        instance = self.new pattern, url_tpl

        options and options.split("\x20").each {|user_opt|
          user_opt.strip!
          next if user_opt.empty?

          opt = user_opt.downcase

          if Source.is_platform? opt
            instance.platform = opt.to_sym
          elsif type = ReaPack::Index.resolve_type(opt)
            instance.type = type
          elsif opt =~ /\A(nomain)|main(?:=(.+))?\Z/
            if $1 # nomain
              instance.main = false
            elsif $2 # explicit sections
              instance.main = $2.split(',').reject(&:empty?).map {|s| s.to_sym }
            else # implicit sections
              instance.main = true
            end
          else
            raise Error, "unknown option '#{user_opt}'"
          end
        }

        instance
      end
    end
  end
end

class ReaPack::Index::CLI
  PROGRAM_NAME = 'reapack-index'.freeze

  CONFIG_SEARCH = [
    '~',
    '.',
  ].freeze

  DEFAULTS = {
    check: false,
    commit: nil,
    message: 'index: $changelog',
    ignore: [],
    output: 'index.xml',
    progress: true,
    quiet: false,
    rebuild: false,
    scan: [],
    strict: false,
    url_template: 'auto',
    verbose: false,
    warnings: true,
  }.freeze

  def read_config
    CONFIG_SEARCH.each {|dir|
      dir = expand_path dir
      path = File.expand_path '.reapack-index.conf', dir

      log 'reading configuration from %s' % path

      unless File.readable? path
        log 'configuration file is unreadable, skipping'
        next
      end

      opts = Shellwords.split File.read(path)
      @opts = parse_options(opts, dir).merge @opts
    }
  rescue ArgumentError => e
    raise ReaPack::Index::Error, e.message
  end

  def parse_options(args, basepath = nil)
    opts = Hash.new

    OptionParser.new do |op|
      op.program_name = PROGRAM_NAME
      op.version = ReaPack::Index::VERSION
      op.banner = "Package indexer for git-based ReaPack repositories\n" +
        "Usage: #{PROGRAM_NAME} [options] [directory]"

      op.separator 'Modes:'

      op.on '-c', '--check', 'Test every package including uncommited changes and exit' do
        opts[:check] = true
      end

      op.on '-s', '--scan [PATH|COMMIT]', 'Scan new commits (default), a path or a specific commit' do |commit|
        opts[:check] = opts[:rebuild] = false
        opts[:scan] ||= []

        if commit
          opts[:scan] << expand_path(commit.strip, base: basepath, relative: true)
        else
          opts[:scan].clear
        end
      end

      op.on '--no-scan', 'Do not scan for new commits' do
        opts[:scan] = false
      end

      op.on '--rebuild', 'Clear the index and rescan the whole git history' do
        opts[:check] = false
        opts[:rebuild] = true
      end

      op.separator 'Indexer options:'

      op.on '-a', '--[no-]amend', 'Update existing versions' do |bool|
        opts[:amend] = bool
      end

      op.on '-i', '--ignore PATH', "Don't check or index any file starting with PATH" do |path|
        opts[:ignore] ||= []
        opts[:ignore] << expand_path(path, base: basepath)
      end

      op.on '-o', "--output FILE=#{DEFAULTS[:output]}",
          'Set the output filename and path for the index' do |file|
        opts[:output] = expand_path(file.strip, base: basepath, relative: true)
      end

      op.on '--[no-]strict', 'Enable strict validation mode' do |bool|
        opts[:strict] = bool
      end

      op.on '-U', "--url-template TEMPLATE=#{DEFAULTS[:url_template]}",
          'Set the template for implicit download links' do |tpl|
        opts[:url_template] = tpl.strip
      end

      op.separator 'Repository metadata:'

      op.on '-n', '--name NAME', 'Set the name shown in ReaPack for this repository' do |name|
        opts[:name] = name.strip
      end

      op.on '-l', '--link LINK', 'Add or remove a website link' do |link|
        opts[:links] ||= Array.new
        opts[:links] << [:website, link.strip]
      end

      op.on '--screenshot-link LINK', 'Add or remove a screenshot link' do |link|
        opts[:links] ||= Array.new
        opts[:links] << [:screenshot, link.strip]
      end

      op.on '--donation-link LINK', 'Add or remove a donation link' do |link|
        opts[:links] ||= Array.new
        opts[:links] << [:donation, link.strip]
      end

      op.on '--ls-links', 'Display the link list then exit' do
        opts[:lslinks] = true
      end

      op.on '-A', '--about=FILE', 'Set the about content from a file' do |file|
        opts[:about] = expand_path file.strip, base: basepath, relative: true
      end

      op.on '--remove-about', 'Remove the about content from the index' do
        opts[:rmabout] = true
      end

      op.on '--dump-about', 'Dump the raw about content in RTF and exit' do
        opts[:dump_about] = true
      end

      op.separator 'Misc options:'

      op.on '--[no-]progress', 'Enable or disable progress information' do |bool|
        opts[:progress] = bool
      end

      op.on '-V', '--[no-]verbose', 'Activate diagnosis messages' do |bool|
        opts[:verbose] = bool
      end

      op.on '-C', '--[no-]commit', 'Select whether to commit the modified index' do |bool|
        opts[:commit] = bool
      end

      op.on '--prompt-commit', 'Ask at runtime whether to commit the index' do
        opts[:commit] = nil
      end

      op.on '-m', "--commit-template MESSAGE",
        'Customize the commit message. Supported placeholder: $changelog' do |msg|
        opts[:message] = msg
      end

      op.on '-W', '--warnings', 'Enable warnings' do
        opts[:warnings] = true
      end

      op.on '-w', '--no-warnings', 'Turn off warnings' do
        opts[:warnings] = false
      end

      op.on '-q', '--[no-]quiet', 'Disable almost all output' do
        opts[:warnings] = false
        opts[:progress] = false
        opts[:verbose] = false
        opts[:quiet] = true
      end

      op.on '--no-config', 'Bypass the configuration files' do
        opts[:noconfig] = true
      end

      op.on_tail '-v', '--version', 'Display version information' do
        puts op.ver
        throw :stop, true
      end

      op.on_tail '-h', '--help', 'Prints this help' do
        puts op
        throw :stop, true
      end
    end.parse! args

    if basepath && !args.empty?
      raise OptionParser::InvalidOption, "#{args.first}"
    end

    opts
  rescue OptionParser::ParseError => e
    $stderr.puts "#{PROGRAM_NAME}: #{e.message}"
    $stderr.puts "Try '#{PROGRAM_NAME} --help' for more information."
    throw :stop, false
  end
end

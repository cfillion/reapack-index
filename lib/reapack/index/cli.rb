class ReaPack::Index::CLI
  CONFIG_SEARCH = [
    '~',
    '.',
  ].freeze

  PROGRAM_NAME = 'reapack-indexer'.freeze

  DEFAULTS = {
    verbose: false,
    warnings: true,
    progress: true,
    quiet: false,
    commit: nil,
    output: './index.xml',
  }.freeze

  def initialize(argv = [])
    @opts = parse_options(argv)
    path = argv.last || Dir.pwd

    return unless @exit.nil?

    @git = Rugged::Repository.discover path
    @opts = parse_options(read_config).merge @opts unless @opts[:noconfig]

    @opts = DEFAULTS.merge @opts

    log @opts.inspect if @exit.nil?
  rescue Rugged::OSError, Rugged::RepositoryError => e
    $stderr.puts e.message
    @exit = false
  end

  def run
    return @exit unless @exit.nil?

    if @git.empty?
      $stderr.puts 'Current branch is empty, cannot continue.'
      return false
    end

    @db = ReaPack::Index.new File.expand_path(@opts[:output], @git.workdir)
    @db.source_pattern = ReaPack::Index.source_for @git.remotes['origin'].url
    @db.amend = @opts[:amend]

    commits = commits_since @db.commit

    @done, @total = 0, commits.size

    unless commits.empty?
      print_progress
      commits.each {|commit| process commit }
      $stderr.print "\n" if @add_nl
    end

    unless @db.modified?
      $stderr.puts 'Nothing to do!' unless @opts[:quiet]
      return true
    end

    # changelog will be cleared by Index#write!
    changelog = @db.changelog
    puts changelog unless @opts[:quiet]

    @db.write!
    commit changelog

    true
  end

private
  def prompt(question, &block)
    $stderr.print "#{question} [y/N] "
    answer = $stdin.getch
    $stderr.puts answer

    yes = answer.downcase == 'y'
    block[] if block_given? && yes

    yes
  end

  def commits_since(last_id)
    walker = Rugged::Walker.new @git
    walker.sorting Rugged::SORT_TOPO | Rugged::SORT_REVERSE
    walker.push @git.head.target_id
    walker.hide last_id if last_id

    walker.each.to_a
  end

  def process(commit)
    if @opts[:verbose]
      sha = commit.oid[0..6]
      message = commit.message.lines.first.chomp
      log "processing %s: %s" % [sha, message]
    end

    @db.commit = commit.oid
    @db.files = lsfiles commit.tree

    parent = commit.parents.first

    if parent
      diff = parent.diff commit.oid
    else
      diff = commit.diff
    end

    diff.each_delta {|delta| index delta, parent.nil? }
  ensure
    @done += 1
    print_progress
  end

  def index(delta, is_initial)
    if is_initial
      status = 'new'
      file = delta.old_file
    else
      status = delta.status
      file = delta.new_file
    end

    return unless ReaPack::Index.type_of file[:path]

    log "-> indexing #{status} file #{file[:path]}"

    if status == :deleted
      @db.remove file[:path]
    else
      blob = @git.lookup file[:oid]

      begin
        @db.scan file[:path], blob.content.force_encoding("UTF-8")
      rescue ReaPack::Index::Error => e
        warn e.message
      end
    end
  end

  def lsfiles(tree, base = String.new)
    files = []

    tree.each {|obj|
      fullname = base.empty? ? obj[:name] : File.join(base, obj[:name])
      case obj[:type]
      when :blob
        files << fullname
      when :tree
        files.concat lsfiles(@git.lookup(obj[:oid]), fullname)
      end
    }

    files
  end

  def commit(changelog)
    return if @opts[:commit] == false || (@opts[:commit].nil? && !prompt('Commit the new index?'))

    target = @git.head.target
    root = Pathname.new @git.workdir
    file = Pathname.new @db.path

    old_index = @git.index
    old_index.read_tree target.tree

    index = @git.index
    index.add file.relative_path_from(root).to_s

    Rugged::Commit.create @git, \
      tree: index.write_tree(@git),
      message: "index: #{changelog}",
      parents: [target],
      update_ref: 'HEAD'

    old_index.write

    $stderr.puts 'commit created'
  end

  def log(line)
    $stderr.puts line if @opts[:verbose]
  end

  def warn(line)
    return unless @opts[:warnings]

    if @add_nl
      $stderr.puts
      @add_nl = false
    end

    $stderr.puts "Warning: #{line}".yellow
  end

  def print_progress
    return if @opts[:verbose] || !@opts[:progress]

    percent = (@done.to_f / @total) * 100
    $stderr.print "\rIndexing commit %d of %d (%d%%)..." %
      [[@done + 1, @total].min, @total, percent]

    @add_nl = true
  end

  def parse_options(args)
    opts = Hash.new

    OptionParser.new do |op|
      op.program_name = PROGRAM_NAME
      op.version = ReaPack::Index::VERSION
      op.banner = "Package indexer for ReaPack-based repositories\n" +
        "Usage: #{PROGRAM_NAME} [options] [directory]"

      op.separator 'Options:'

      op.on '-a', '--[no-]amend', 'Reindex existing versions' do |bool|
        opts[:amend] = bool
      end

      op.on '-o', "--output FILE=#{DEFAULTS[:output]}",
          'Set the output filename and path for the index' do |file|
        opts[:output] = file.strip
      end

      op.on '--[no-]progress', 'Enable or disable progress information' do |bool|
        opts[:progress] = bool
      end

      op.on '-V', '--[no-]verbose', 'Activate diagnosis messages' do |bool|
        opts[:verbose] = bool
      end

      op.on '-c', '--[no-]commit', 'Select whether to commit the modified index' do |bool|
        opts[:commit] = bool
      end

      op.on '--prompt-commit', 'Ask at runtime whether to commit the index' do
        opts[:commit] = nil
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
        @exit = true
      end

      op.on_tail '-h', '--help', 'Prints this help' do
        puts op
        @exit = true
      end
    end.parse! args

    opts
  rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
    $stderr.puts "#{PROGRAM_NAME}: #{e.message}"
    $stderr.puts "Try '#{PROGRAM_NAME} --help' for more information."
    @exit = false
    opts
  end

  def read_config
    CONFIG_SEARCH.map {|dir|
      dir = File.expand_path dir, @git.workdir
      path = File.expand_path '.reapack-index.conf', dir

      log 'reading configuration from %s' % path

      unless File.readable? path
        log 'configuration file is unreadable, skipping'
        next
      end

      opts = Array.new
      File.foreach(path) {|line| opts << Shellwords.split(line) }
      opts
    }.flatten.compact
  end
end

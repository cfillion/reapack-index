class ReaPack::Index::Indexer
  CONFIG_SEARCH = [
    '~',
    '.',
  ].freeze

  PROGRAM_NAME = 'reapack-indexer'.freeze

  DiffEntry = Struct.new :file, :action, :blob

  def initialize(args)
    @path = args.last || Dir.pwd
    parse_options read_config + args

    return unless @exit.nil?

    @git = Rugged::Repository.discover @path

    @db = ReaPack::Index.new File.expand_path(@output, @git.workdir)
    @db.source_pattern = ReaPack::Index.source_for @git.remotes['origin'].url
    @db.amend = @amend
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

    branch = @git.head.name['refs/heads/'.size..-1]

    if branch != 'master'
      return false unless prompt("Current branch #{branch} is not" \
        " the master branch. Continue anyway?")
    end

    walker = Rugged::Walker.new @git
    walker.sorting Rugged::SORT_TOPO | Rugged::SORT_REVERSE
    walker.push @git.head.target_id
    walker.hide @db.commit if @db.commit

    commits = walker.each.to_a

    @done, @total = 0, commits.size
    print_progress if @total > 0

    commits.each {|commit| process commit }

    if @total > 0 && @progress
      $stderr.print "\n"
    end

    unless @db.modified?
      $stderr.puts 'Nothing to do!' unless @quiet
      return true
    end

    # changelog will be cleared by Index#write!
    changelog = @db.changelog
    puts changelog unless @quiet

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

  def process(commit)
    if @verbose
      sha = commit.oid[0..6]
      message = commit.message.lines.first.chomp
      log "Processing %s: %s" % [sha, message]
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
        warn "Warning: #{e.message}".yellow
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
    return if @commit == false || (@commit.nil? && !prompt('Commit the new index?'))

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
    $stderr.puts line if @verbose
  end

  def warn(line)
    return unless @warnings

    if @add_nl
      line.prepend "\n"
      @add_nl = false
    end

    Kernel.warn line
  end

  def print_progress
    return if @verbose || !@progress

    percent = (@done.to_f / @total) * 100
    $stderr.print "\rIndexing commit %d of %d (%d%%)..." %
      [[@done + 1, @total].min, @total, percent]

    @add_nl = true
  end

  def parse_options(args)
    @verbose = false
    @warnings = true
    @progress = true
    @quiet = false
    @commit = nil
    @output = './index.xml'

    OptionParser.new do |opts|
      opts.program_name = PROGRAM_NAME
      opts.version = ReaPack::Index::VERSION
      opts.banner = "Package indexer for ReaPack-based repositories\n" +
        "Usage: #{PROGRAM_NAME} [options] [directory]"

      opts.separator 'Options:'

      opts.on '-a', '--[no-]amend', 'Reindex existing versions' do |bool|
        @amend = bool
      end

      opts.on '-o', "--output FILE=#{@output}",
          'Set the output filename and path for the index' do |file|
        @output = file.strip
      end

      opts.on '--[no-]progress', 'Enable or disable progress information' do |bool|
        @progress = bool
      end

      opts.on '-V', '--[no-]verbose', 'Activate diagnosis messages' do |bool|
        @verbose = bool
      end

      opts.on '-c', '--[no-]commit', 'Select whether to commit the modified index' do |bool|
        @commit = bool
      end

      opts.on '-W', '--warnings', 'Enable warnings' do
        @warnings = true
      end

      opts.on '-w', '--no-warnings', 'Turn off warnings' do
        @warnings = false
      end

      opts.on '-q', '--[no-]quiet', 'Disable almost all output' do |bool|
        @warnings = false
        @progress = false
        @verbose = false
        @quiet = true
      end

      opts.on_tail '-v', '--version', 'Display version information' do
        puts opts.ver
        @exit = true
      end

      opts.on_tail '-h', '--help', 'Prints this help' do
        puts opts
        @exit = true
      end
    end.parse! args
  rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
    $stderr.puts "#{PROGRAM_NAME}: #{e.message}"
    @exit = false
  end

  def read_config
    CONFIG_SEARCH.map {|dir|
      dir = File.expand_path dir, @path
      path = File.expand_path '.reapack-index.conf', dir
      next unless File.readable? path

      opts = Array.new
      File.foreach(path) {|line| opts << Shellwords.split(line) }
      opts
    }.flatten.compact
  end
end

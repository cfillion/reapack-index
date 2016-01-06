class ReaPack::Index::Indexer
  CONFIG_SEARCH = [
    '~',
    '.',
  ].freeze

  def initialize(args)
    parse_options read_config + args

    @git = Git.open @path

    @db = ReaPack::Index.new File.expand_path(@output, @git.dir.to_s)
    @db.pwd = @path
    @db.source_pattern = ReaPack::Index.source_for @git.remote.url
  end

  def run
    @done = 0

    branch = @git.current_branch

    if branch.nil?
      Kernel.warn 'Current branch is empty, cannot continue.'
      abort
    elsif branch != 'master'
      abort unless prompt("Current branch #{@git.current_branch} is not" \
        " the master branch. Continue anyway?")
    end

    if @db.commit
      commits = @git.log(999999).between @db.commit
    else
      commits = @git.log 999999
    end

    @total = commits.size
    commits.reverse_each {|commit| process commit }

    if @total > 0
      unless @verbose
        # bump to 100%
        update_progress
        print "\n"
      end

      print "\n"
    end

    unless @db.modified?
      puts 'Nothing to do!'
      return
    end

    changelog = @db.changelog
    puts changelog

    @db.write!

    prompt 'Commit the new database?' do
      @git.add @db.path
      @git.commit "index: #{changelog}"

      puts 'done'
    end
  end

private
  def prompt(question, &block)
    print "#{question} [y/N] "
    answer = STDIN.getch
    puts answer

    yes = answer.downcase == 'y'
    block[] if block_given? && yes

    yes
  end

  def scan(path, contents, &block)
    @db.scan path, contents, &block
  rescue ReaPack::Index::Error => e
    warn "Warning: #{e.message}".yellow
  end

  def process(commit)
    if @verbose
      sha = commit.sha[0..6]
      message = commit.message.lines.first.chomp
      log "Processing %s: %s" % [sha, message]
    else
      update_progress
    end

    @db.commit = commit.sha
    parent = commit.parent

    files = lsfiles commit.gtree

    # initial commit
    unless parent
      files.each do |path|
        next unless ReaPack::Index.type_of path

        log "-> indexing new file #{path}"

        blob = commit.gtree.files[path]

        scan(path, blob.contents) {|file|
          files.include? file
        }
      end

      return
    end

    diffs = ReaPack::Index::GitDiff.new(@git, commit.parent.sha, commit.sha).to_a
    diffs.each {|diff|
      next unless ReaPack::Index.type_of diff.path

      log "-> indexing #{diff.type} file #{diff.path}"

      if diff.type == 'deleted'
        @db.remove diff.path
      else
        scan(diff.path, diff.blob.contents) {|file|
          files.include? file
        }
      end
    }
  rescue NoMethodError => e
    warn "Error: #{e}".red
  ensure
    @done += 1
  end

  def lsfiles(tree)
    files = tree.files.keys

    tree.trees.each {|pair|
      prefix = pair.first

      subfiles = lsfiles(pair.last).map do |f|
        File.join prefix, f
      end

      files.concat subfiles
    }

    files
  end

  def log(line)
    puts line if @verbose
  end

  def warn(line)
    return unless @warnings

    if @add_nl
      line.prepend "\n"
      @add_nl = false
    end

    Kernel.warn line
  end

  def update_progress
    percent = (@done.to_f / @total) * 100
    print "\rIndexing commit %d of %d (%d%%)..." %
      [[@done + 1, @total].min, @total, percent]

    @add_nl = true
  end

  def parse_options(args)
    @verbose = false
    @warnings = true
    @output = './index.xml'

    OptionParser.new do |opts|
      opts.program_name = 'reapack-indexer'
      opts.version = ReaPack::Index::VERSION
      opts.banner = "Package indexer for ReaPack-based repositories\n" +
        "Usage: #{opts.program_name} [options] [directory]"

      opts.separator 'Options:'

      opts.on '-a', '--[no-]amend', 'Reindex existing versions' do |bool|
        @db.amend = bool
      end

      opts.on '-o', "--output FILE=#{@output}",
          'Set the output path of the database' do |file|
        @output = file.strip
      end

      opts.on '-V', '--[no-]verbose', 'Run verbosely' do |bool|
        @verbose = bool
      end

      opts.on '-W', '--warnings', 'Enable all warnings' do
        @warnings = true
      end

      opts.on '-w', '--no-warnings', 'Turn off warnings' do
        @warnings = false
      end

      opts.on_tail '-v', '--version', 'Display version information' do
        puts opts.ver
        exit
      end

      opts.on_tail '-h', '--help', 'Prints this help' do
        puts opts
        exit
      end
    end.parse! args

    @path = args.last || Dir.pwd
  rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
    Kernel.warn "reapack-indexer: #{e.message}"
    exit
  end

  def read_config
    CONFIG_SEARCH.map {|dir|
      path = File.expand_path '.reapack-index.conf', dir
      next unless File.readable? path

      opts = Array.new
      File.foreach(path) {|line| opts << Shellwords.split(line) }
      opts
    }.flatten.compact
  end
end

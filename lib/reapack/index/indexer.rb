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

    @git = Git.open @path

    @db = ReaPack::Index.new File.expand_path(@output, @git.dir.to_s)
    @db.source_pattern = ReaPack::Index.source_for @git.remote.url
    @db.amend = @amend
  end

  def run
    pwd = Dir.pwd

    return @exit unless @exit.nil?

    # This fixes lsfiles when running the indexer from
    # a subdirectory of the git repository root.
    # It would return an empty array without this.
    Dir.chdir @path

    branch = @git.current_branch

    if branch.nil?
      Kernel.warn 'Current branch is empty, cannot continue.'
      return false
    elsif branch != 'master'
      return false unless prompt("Current branch #{@git.current_branch} is not" \
        " the master branch. Continue anyway?")
    end

    if @db.commit
      commits = @git.log(999999).between @db.commit
    else
      commits = @git.log 999999
    end

    @done, @total = 0, commits.size
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
      return true
    end

    changelog = @db.changelog
    puts changelog

    @db.write!

    prompt 'Commit the new index?' do
      @git.add @db.path
      @git.commit "index: #{changelog}"

      puts 'done'
    end

    true
  ensure
    Dir.chdir pwd
  end

private
  def prompt(question, &block)
    print "#{question} [y/N] "
    answer = $stdin.getch
    puts answer

    yes = answer.downcase == 'y'
    block[] if block_given? && yes

    yes
  end

  def scan(path, contents)
    @db.scan path, contents
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
    @db.files = lsfiles commit.gtree

    parent = commit.parent
    entries = []

    if parent
      ReaPack::Index::GitDiff.new(@git, parent.sha, commit.sha).each {|diff|
        entry = DiffEntry.new diff.path, diff.type, diff.blob
        entries << entry
      }
    else
      # initial commit
      @db.files.each {|path|
        entry = DiffEntry.new path, 'new', get_blob(path, commit.gtree)
        entries << entry
      }
    end

    entries.each {|entry|
      next unless ReaPack::Index.type_of entry.file

      log "-> indexing #{entry.action} file #{entry.file}"

      if entry.action == 'deleted'
        @db.remove entry.file
      else
        scan entry.file, entry.blob.contents
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

  def get_blob(path, tree)
    directories = path.split File::SEPARATOR
    directories.shift if directories.first == '.'
    file = directories.pop

    directories.each {|dir| tree = tree.trees[dir] }

    tree.files[file]
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
        @exit = true
      end

      opts.on_tail '-h', '--help', 'Prints this help' do
        puts opts
        @exit = true
      end
    end.parse! args
  rescue OptionParser::InvalidOption, OptionParser::MissingArgument => e
    Kernel.warn "#{PROGRAM_NAME}: #{e.message}"
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

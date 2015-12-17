class ReaPack::Index::Indexer
  def initialize(path)
    @git = Git.open path

    @db = ReaPack::Index.new File.join(@git.dir.to_s, 'index.xml')
    @db.pwd = path
    @db.source_pattern = ReaPack::Index.source_for @git.remote.url

    parse_options
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
      update_progress unless @verbose
      print "\n"
    end

    unless @db.modified?
      puts 'The database was not modified!'
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
    warn "Warning: #{e.message}"
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

    files = commit.gtree.files

    # initial commit
    unless parent
      files.each_pair do |path, blob|
        next unless ReaPack::Index.type_of path

        log "-> indexing new file #{path}"
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
          files.find {|array| array.first == file }
        }
      end
    }
  rescue NoMethodError => e
    warn "Error: #{e}"
  ensure
    @done += 1
  end

  def log(line)
    puts line if @verbose
  end

  def warn(line)
    return unless @warnings

    line.prepend "\n" unless @verbose

    Kernel.warn line
  end

  def update_progress
    percent = (@done.to_f / @total) * 100
    print "\rIndexing commit %d of %d (%d%%)..." %
      [[@done + 1, @total].min, @total, percent]
  end

  def parse_options
    @verbose = false
    @warnings = true

    OptionParser.new do |opts|
      opts.banner = "Usage: reapack-indexer [options]"

      opts.on "-v", "--[no-]verbose", "Run verbosely" do |bool|
        @verbose = bool
      end

      opts.on "-W", "--[no-]warnings", "Enable or disable warnings" do |bool|
        @warnings = bool
      end

      opts.on "-h", "--help", "Prints this help" do
        puts opts
        exit
      end
    end.parse!
  rescue OptionParser::InvalidOption => e
    Kernel.warn "reapack-indexer: #{e.message}"
    exit
  end
end

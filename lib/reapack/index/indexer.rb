class ReaPack::Index::Indexer
  def initialize(path)
    @git = Git.open path

    @db = ReaPack::Index.new File.join(@git.dir.to_s, 'index.xml')
    @db.source_pattern = ReaPack::Index.source_for @git.remote.url

    parse_options
  end

  def run
    @done = 0

    if @git.current_branch != 'master'
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

    update_progress unless @verbose
    print "\n" if @total > 0

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

  def scan(path, contents)
    @db.scan path, contents
  rescue RuntimeError => e
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

    # initial commit
    unless parent
      commit.gtree.files.each_pair {|path, blob|
        next unless ReaPack::Index.type_of path

        log "-> indexing new file #{path}"
        scan path, blob.contents
      }

      return
    end

    diff = ReaPack::Index::GitDiff.new(@git, commit.parent.sha, commit.sha).to_a
    diff.each {|diff|
      next unless ReaPack::Index.type_of diff.path

      log "-> indexing #{diff.type} file #{diff.path}"

      if diff.type == 'deleted'
        @db.delete diff.path
      else
        scan diff.path, diff.blob.contents
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
      [@done, @total, percent]
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

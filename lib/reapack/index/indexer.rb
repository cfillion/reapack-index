class ReaPack::Index::Indexer
  def initialize(path)
    @git = Git.open path

    @db = ReaPack::Index.new File.join(@git.dir.to_s, 'index.xml')
    @db.source_pattern = ReaPack::Index.source_for @git.remote.url
  end

  def run
    if @git.current_branch != 'master'
      abort unless prompt("Current branch #{@git.current_branch} is not" \
        " the master branch. Continue anyway?")
    end

    if @db.commit
      commits = @git.log(999999).between @db.commit
    else
      commits = @git.log 999999
    end

    commits.reverse_each {|commit| process commit }
    puts

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
    puts "Processing #{commit.message.lines.first.chomp} (#{commit.sha[0..6]})..."

    @db.commit = commit.sha
    parent = commit.parent

    # initial commit
    unless parent
      commit.gtree.files.each_pair {|path, blob|
        next unless ReaPack::Index.type_of path

        puts "-> indexing new file #{path}"
        scan path, blob.contents
      }

      return
    end

    Git::Diff.new(@git, commit.parent.sha, commit.sha).each {|diff|
      next unless ReaPack::Index.type_of diff.path

      puts "-> indexing #{diff.type} file #{diff.path}"

      if diff.type == 'deleted'
        @db.delete diff.path
      else
        scan diff.path, diff.blob.contents
      end
    }
  end
end

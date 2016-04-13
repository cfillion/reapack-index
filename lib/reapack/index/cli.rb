class ReaPack::Index
  class CLI
  def initialize(argv = [])
    @opts = parse_options(argv)
    path = argv.last || Dir.pwd

    return unless @exit.nil?

    @git = Git.new path
    @opts = parse_options(read_config).merge @opts unless @opts[:noconfig]

    @opts = DEFAULTS.merge @opts

    log Hash[@opts.sort].inspect if @exit.nil?
  rescue Rugged::OSError, Rugged::RepositoryError => e
    $stderr.puts e.message
    @exit = false
  end

  def run
    return @exit unless @exit.nil?

    @db = ReaPack::Index.new expand_path(@opts[:output])
    @db.amend = @opts[:amend]

    set_url_template

    if @opts[:check]
      return check
    end

    if @opts[:lslinks]
      print_links
      return true
    end

    if @opts[:dump_about]
      print @db.description
      return true
    end

    do_name; do_about; eval_links; scan_commits

    unless @db.modified?
      $stderr.puts 'Nothing to do!' unless @opts[:quiet]
      return success_code
    end

    # changelog will be cleared by Index#write!
    changelog = @db.changelog
    puts changelog unless @opts[:quiet]

    @db.write!
    commit changelog

    success_code
  end

private
  def success_code
    @exit.nil? ? true : @exit
  end

  def set_url_template
    tpl = @opts[:url_template]
    is_custom = tpl != DEFAULTS[:url_template]

    @db.url_template = is_custom ? tpl : @git.guess_url_template
  rescue ReaPack::Index::Error => e
    warn '--url-template: ' + e.message if is_custom
  end

  def scan_commits
    if @git.empty?
      warn 'The current branch does not contains any commit.'
      return
    end

    if @opts[:scan].empty?
      commits = @git.commits_since @db.commit.to_s
    else
      commits = @opts[:scan].map {|hash|
        @git.get_commit hash or begin
          $stderr.puts '--scan: bad revision: %s' % @opts[:scan]
          @exit = false
          nil
        end
      }.compact
    end

    unless commits.empty?
      progress_wrapper commits.size do
        commits.each {|commit| process commit }
      end
    end
  end

  def process(commit)
    if @opts[:verbose]
      log 'processing %s: %s' % [commit.short_id, commit.summary]
    end

    @db.commit = commit.id
    @db.time = commit.time
    @db.files = commit.filelist

    commit.each_diff {|diff| index diff }
  ensure
    bump_progress
  end

  def index(diff)
    return if ignored? expand_path(diff.file)
    return unless ReaPack::Index.type_of diff.file

    log "-> indexing #{diff.status} file #{diff.file}"

    if diff.status == :deleted
      @db.remove diff.file
    else
      begin
        @db.scan diff.file, diff.new_content
      rescue ReaPack::Index::Error => e
        warn "#{diff.file}: #{e.message}"
      end
    end
  end

  def eval_links
    Array(@opts[:links]).each {|link|
      begin
        @db.eval_link *link
      rescue ReaPack::Index::Error => e
        opt = case link.first
        when :website
          '--link'
        when :donation
          '--donation-link'
        end

        warn "#{opt}: " + e.message
      end
    }
  end

  def print_links
    ReaPack::Index::Link::VALID_TYPES.each {|type|
      prefix = "[#{type}]".bold.light_black
      @db.links(type).each {|link|
        display = link.name == link.url ? link.url : '%s (%s)' % [link.name, link.url]
        puts '%s %s' % [prefix, display]
      }
    }
  end

  def do_name
    @db.name = @opts[:name] if @opts[:name]
    check_name
  rescue ReaPack::Index::Error => e
    warn '--name: ' + e.message
  end

  def check_name
    if @db.name.empty?
      warn 'This index is unnamed. ' \
        'Run the following command to set a name of your choice:' \
        "\n  #{File.basename $0} --name 'FooBar Scripts'"
    end
  end

  def do_about
    path = @opts[:about]

    unless path
      @db.description = String.new if @opts[:rmabout]
      return
    end

    log "converting #{path} into RTF..."

    # look for the file in the working directory, not on the repository root
    @db.description = File.read(path)
  rescue Errno::ENOENT => e
    warn '--about: ' + e.message.sub(' @ rb_sysopen', '')
  rescue ReaPack::Index::Error => e
    warn e.message
  end

  def check
    check_name

    @db.amend = true # enable checks for released versions as well
    failures = []

    pkgs = Hash[Dir.glob("#{Regexp.quote(@git.path)}/**/*").sort.map {|abs|
      rel = @git.relative_path abs
      @db.files << rel

      next if !File.file?(abs) || ignored?(abs) || !ReaPack::Index.type_of(abs)

      [abs, rel]
    }.compact]

    pkgs.each_pair {|abs, rel|
      begin
        @db.scan rel, File.read(abs)

        if @opts[:verbose]
          $stderr.puts '%s: passed' % rel
        elsif !@opts[:quiet]
          $stderr.print '.'
        end
      rescue ReaPack::Index::Error => e
        if @opts[:verbose]
          $stderr.puts '%s: failed' % rel
        elsif !@opts[:quiet]
          $stderr.print 'F'
        end

        prefix = "\n\x20\x20"
        failures << "%s failed:#{prefix}%s" %
          [rel, e.message.gsub("\n", prefix).yellow]
      end
    }

    $stderr.puts "\n" unless @opts[:quiet] || @opts[:verbose]

    failures.each_with_index {|msg, index|
      $stderr.puts unless @opts[:quiet] && index == 0
      $stderr.puts '%d) %s' % [index + 1, msg]
    }

    unless @opts[:quiet]
      $stderr.puts "\n"
      $stderr.puts 'Finished checks for %d package%s with %d failure%s' % [
        pkgs.size, pkgs.size == 1 ? '' : 's',
        failures.size, failures.size == 1 ? '' : 's',
      ]
    end

    failures.empty?
  end

  def commit(changelog)
    return unless case @opts[:commit]
    when false, true
      @opts[:commit]
    else
      prompt 'Commit the new index?'
    end

    @git.create_commit "index: #{changelog}", [@db.path]
    $stderr.puts 'commit created'
  end

  def prompt(question, &block)
    $stderr.print "#{question} [y/N] "
    answer = $stdin.getch
    $stderr.puts answer

    yes = answer.downcase == 'y'
    block[] if block_given? && yes

    yes
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

    $stderr.puts "warning: #{line}".yellow
  end

  def progress_wrapper(total, &block)
    @done, @total = 0, total
    print_progress
    block[]
    $stderr.print "\n" if @add_nl
  end

  def bump_progress
    @done += 1
    print_progress
  end

  def print_progress
    return if @opts[:verbose] || !@opts[:progress]

    percent = (@done.to_f / @total) * 100
    $stderr.print "\rIndexing commit %d of %d (%d%%)..." %
      [[@done + 1, @total].min, @total, percent]

    @add_nl = true
  end

  def ignored?(path)
    path = path + '/'

    @opts[:ignore].each {|pattern|
      return true if path.start_with? pattern + '/'
    }

    false
  end

  def expand_path(path)
    # expand from the repository root or from the current directory if
    # the repository is not yet initialized
    File.expand_path path, @git ? @git.path : Dir.pwd
  end
  end
end

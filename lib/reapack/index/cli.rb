class ReaPack::Index::CLI
  attr_reader :index

  def initialize(argv = [])
    @opts = parse_options argv

    @git = ReaPack::Index::Git.new argv.first || Dir.pwd
    log "found git repository in #{@git.path}"

    read_config unless @opts[:noconfig]

    unless @opts[:output]
      @opts[:output] = expand_path DEFAULTS[:output], relative: true
    end

    @opts = DEFAULTS.merge @opts

    log Hash[@opts.sort].inspect

    @index = ReaPack::Index.new File.expand_path(@opts[:output])
    @index.amend = @opts[:amend]
    @index.strict = @opts[:strict]
    set_url_template
  rescue Rugged::OSError, Rugged::RepositoryError, ReaPack::Index::Error => e
    $stderr.puts e.message
    throw :stop, false
  end

  def run
    if @opts[:check]
      return do_check
    end

    if @opts[:lslinks]
      print_links
      return true
    end

    if @opts[:dump_about]
      print @index.about
      return true
    end

    do_name; do_about; eval_links; do_scan

    unless @index.modified?
      $stderr.puts 'Nothing to do!' unless @opts[:quiet]
      return true
    end

    # changelog will be cleared by Index#write!
    changelog = @index.changelog
    puts changelog unless @opts[:quiet]

    @index.write!
    commit changelog
    true
  end

private
  def set_url_template
    tpl = @opts[:url_template]
    is_custom = tpl != DEFAULTS[:url_template]

    @index.url_template = is_custom ? tpl : @git.guess_url_template
  rescue ReaPack::Index::Error => e
    warn '--url-template: ' + e.message if is_custom
  end

  def do_scan
    commits = if @opts[:rebuild]
      @index.clear
      @git.commits
    elsif @opts[:scan] == false
      []
    elsif @opts[:scan].empty?
      @git.commits_since @index.last_commit
    else
      @index.auto_bump_commit = false

      # call process_commit only once per commit instead of once per --scan argument
      commits = Hash.new
      @opts[:scan].map {|hash|
        files = @git.last_commits_for @git.relative_path(hash)
        if !files.empty?
          files.each {|commit, files|
            commits[commit] = Array.new unless commits.has_key? commit # keep nil
            commits[commit].concat files unless commits[commit].nil?
          }
        elsif c = @git.get_commit(hash)
          commits[c] = nil
        else
          $stderr.puts "--scan: bad file or revision: '%s'" % hash
          throw :stop, false
        end
      }
      commits.to_a
    end

    unless commits.empty?
      progress_wrapper commits.size do
        commits.each {|args| process_commit *args }
      end
    end
  end

  def process_commit(commit, files = nil)
    if @opts[:verbose]
      log 'processing %s: %s' % [commit.short_id, commit.summary]
    end

    @index.commit = commit.id
    @index.time = commit.time
    @index.files = commit.filelist

    commit.each_diff
      .select {|diff|
        (files.nil? || files.include?(diff.file)) &&
          (not ignored? expand_path(diff.file)) &&
          ReaPack::Index.is_package?(diff.file)
      }
      .sort_by {|diff|
        diff.status == :deleted || diff.new_header[:noindex] ? 0 : 1
      }
      .each {|diff| process_diff diff }
  ensure
    bump_progress
  end

  def process_diff(diff)
    log "-> indexing #{diff.status} file #{diff.file}"

    if diff.status == :deleted
      @index.remove diff.file
    else
      begin
        @index.scan diff.file, diff.new_header
      rescue ReaPack::Index::Error => e
        warn "#{diff.file}:\n#{indent e.message}"
      end
    end
  end

  def eval_links
    Array(@opts[:links]).each {|link|
      begin
        @index.eval_link *link
      rescue ReaPack::Index::Error => e
        opt = case link.first
        when :website
          '--link'
        when :donation
          '--donation-link'
        when :screenshot
          '--screenshot-link'
        end

        warn "#{opt}: " + e.message
      end
    }
  end

  def print_links
    ReaPack::Index::Link::VALID_TYPES.each {|type|
      prefix = "[#{type}]".bold.light_black
      @index.links(type).each {|link|
        display = link.name == link.url ? link.url : '%s (%s)' % [link.name, link.url]
        puts '%s %s' % [prefix, display]
      }
    }
  end

  def do_name
    @index.name = @opts[:name] if @opts[:name]
    check_name
  rescue ReaPack::Index::Error => e
    warn '--name: ' + e.message
  end

  def check_name
    if @index.name.empty?
      warn 'This index is unnamed. ' \
        'Run the following command to set a name of your choice:' \
        "\n  #{File.basename $0} --name 'FooBar Scripts'"
    end
  end

  def do_about
    path = @opts[:about]

    unless path
      @index.about = String.new if @opts[:rmabout]
      return
    end

    log "converting #{path} into RTF..."

    # look for the file in the working directory, not on the repository root
    @index.about = File.read(path)
  rescue Errno::ENOENT => e
    warn '--about: ' + e.message.sub(' @ rb_sysopen', '')
  rescue ReaPack::Index::Error => e
    warn e.message
  end

  def do_check
    check_name

    @index.clear
    failures = []

    pkgs = Hash[Find.find(@git.path).sort.map {|abs|
      rel = @git.relative_path abs
      @index.files << rel

      next if !File.file?(abs) || ignored?(abs) || !ReaPack::Index.is_package?(rel)

      [abs, rel]
    }.compact]

    # reiterate over the pkg list after registering every file
    pkgs.each_pair {|abs, rel|
      begin
        @index.scan rel, MetaHeader.from_file(abs)

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

        failures << "%s failed:\n%s" % [rel, indent(e.message).yellow]
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

    message = @opts[:message].gsub '$changelog', changelog
    @git.create_commit message, [@index.path]
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

  def expand_path(path, **options)
    # expand from the repository root or from the current directory if
    # the repository is not yet initialized
    path = File.expand_path path, options[:base] || (@git ? @git.path : Dir.pwd)

    if options[:relative]
      root = Pathname.new Dir.pwd
      file = Pathname.new path

      file.relative_path_from(root).to_s
    else
      path
    end
  end

  def indent(input)
    output = String.new
    input.each_line {|l| output += "\x20\x20#{l}" }
    output
  end
end

class ReaPack::Index::CLI
  def initialize(argv = [])
    @opts = parse_options(argv)
    path = argv.last || Dir.pwd

    return unless @exit.nil?

    @git = Rugged::Repository.discover path
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

    @db.url_template = is_custom ? tpl : auto_url_tpl
  rescue ReaPack::Index::Error => e
    warn '--url-template: ' + e.message if is_custom
  end

  def scan_commits
    if @git.empty?
      warn 'The current branch does not contains any commit.'
      return
    end

    if @opts[:scan].empty?
      walker = Rugged::Walker.new @git
      walker.sorting Rugged::SORT_TOPO | Rugged::SORT_REVERSE
      walker.push @git.head.target_id

      last_commit = @db.commit.to_s
      walker.hide last_commit if find_commit last_commit

      commits = walker.each.to_a
    else
      commits = @opts[:scan].map {|hash|
        find_commit hash or begin
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

  def find_commit(hash)
    if hash.size.between?(7, 40) && @git.include?(hash)
      object = @git.lookup hash
      object if object.is_a? Rugged::Commit
    end
  rescue Rugged::InvalidError
    nil
  end

  def process(commit)
    if @opts[:verbose]
      sha = commit.oid[0...7]
      message = commit.message.lines.first.chomp
      log 'processing %s: %s' % [sha, message]
    end

    @db.commit = commit.oid
    @db.time = commit.time
    @db.files = lsfiles commit.tree

    parent = commit.parents.first

    if parent
      diff = parent.diff commit.oid
    else
      diff = commit.diff
    end

    diff.each_delta {|delta| index delta, parent.nil? }
  ensure
    bump_progress
  end

  def index(delta, is_initial)
    if is_initial
      status = 'new'
      file = delta.old_file
    else
      status = delta.status
      file = delta.new_file
    end

    return if ignored? expand_path(file[:path])
    return unless ReaPack::Index.type_of file[:path]

    log "-> indexing #{status} file #{file[:path]}"

    if status == :deleted
      @db.remove file[:path]
    else
      blob = @git.lookup file[:oid]

      begin
        @db.scan file[:path], blob.content.force_encoding('UTF-8')
      rescue ReaPack::Index::Error => e
        warn "#{file[:path]}: #{e.message}"
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
    @db.amend = true # enable checks for released versions as well

    check_name

    root = Pathname.new @git.workdir
    failures = []

    pkgs = Hash[Pathname.glob("#{Regexp.quote(root.to_s)}**/*").sort.map {|pn|
      abs, rel = pn.to_s, pn.relative_path_from(root).to_s
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

    old_index = @git.index
    target = @git.empty? ? nil : @git.head.target

    if target
      old_index.read_tree target.tree
    else
      old_index.clear
    end

    index = @git.index
    index.add relative_path(@db.path)

    Rugged::Commit.create @git, \
      tree: index.write_tree(@git),
      message: "index: #{changelog}",
      parents: [target].compact,
      update_ref: 'HEAD'

    old_index.write

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

    $stderr.puts "Warning: #{line}".yellow
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
    File.expand_path path, @git ? @git.workdir : Dir.pwd
  end

  def relative_path(path)
    root = Pathname.new @git.workdir
    file = Pathname.new path

    file.relative_path_from(root).to_s
  end

  def auto_url_tpl
    remote = @git.remotes['origin']
    return unless remote

    uri = Gitable::URI.parse remote.url
    return unless uri.path =~ /\A\/?(?<user>[^\/]+)\/(?<repo>[^\/]+)\.git\Z/

    tpl = uri.to_web_uri
    tpl.path += '/raw/$commit/$path'

    tpl.to_s
  end
end

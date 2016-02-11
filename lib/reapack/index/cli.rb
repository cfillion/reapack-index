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

    log Hash[@opts.sort].inspect if @exit.nil?
  rescue Rugged::OSError, Rugged::RepositoryError => e
    $stderr.puts e.message
    @exit = false
  end

  def run
    return @exit unless @exit.nil?

    @db = ReaPack::Index.new File.expand_path(@opts[:output], @git.workdir)
    @db.amend = @opts[:amend]

    if @opts[:lslinks]
      print_links
      return true
    end

    if @opts[:dump_about]
      print @db.description
      return true
    end

    if remote = @git.remotes['origin']
      @db.source_pattern = ReaPack::Index.source_for remote.url
    end

    set_about
    eval_links
    scan_commits

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

  def scan_commits
    if @git.empty?
      warn 'The current branch does not contains any commit.'
      return
    end

    walker = Rugged::Walker.new @git
    walker.sorting Rugged::SORT_TOPO | Rugged::SORT_REVERSE
    walker.push @git.head.target_id
    walker.hide @db.commit if @db.commit

    commits = walker.each.to_a

    @done, @total = 0, commits.size

    unless commits.empty?
      print_progress
      commits.each {|commit| process commit }
      $stderr.print "\n" if @add_nl
    end
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

  def eval_links
    Array(@opts[:links]).each {|link|
      begin
        @db.eval_link *link
      rescue ReaPack::Index::Error => e
        warn e.message
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

  def set_about
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

  def commit(changelog)
    return unless case @opts[:commit]
    when false, true
      @opts[:commit]
    else
      prompt 'Commit the new index?'
    end

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

      op.on '-l', '--link LINK', 'Add or remove a website link' do |link|
        opts[:links] ||= Array.new
        opts[:links] << [:website, link.strip]
      end

      op.on '--donation-link LINK', 'Add or remove a donation link' do |link|
        opts[:links] ||= Array.new
        opts[:links] << [:donation, link]
      end

      op.on '--ls-links', 'Display the link list then exit' do |link|
        opts[:lslinks] = true
      end

      op.on '-A', '--about=FILE', 'Set the about content from a file' do |file|
        opts[:about] = file.strip
      end

      op.on '--remove-about', 'Remove the about content from the index' do
        opts[:rmabout] = true
      end

      op.on '--dump-about', 'Dump the raw about content in RTF and exit' do
        opts[:dump_about] = true
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

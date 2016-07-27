class ReaPack::Index
  class Git
    def initialize(path)
      @repo = Rugged::Repository.discover path.encode(Encoding::UTF_8)
    end

    def empty?
      @repo.empty?
    end

    def path
      File.expand_path @repo.workdir
    end

    def commits
      commits_since nil
    end

    def commits_since(sha)
      return [] if empty?

      walker = Rugged::Walker.new @repo
      walker.sorting Rugged::SORT_TOPO | Rugged::SORT_REVERSE
      walker.push @repo.head.target_id

      walker.hide sha if fetch_commit sha

      walker.map {|c| Commit.new c, @repo }
    end

    def get_commit(sha)
      c = fetch_commit sha
      Commit.new c, @repo if c
    end

    def last_commit
      c = @repo.last_commit
      Commit.new c, @repo if c
    end

    def last_commit_for(file)
      commits.reverse_each.find {|c|
        c.each_diff.any? {|d| d.file == file }
      }
    end

    def guess_url_template
      remote = @repo.remotes['origin']
      return unless remote

      uri = Gitable::URI.parse remote.url
      return unless uri.path =~ /\A\/?(?<user>[^\/]+)\/(?<repo>[^\/]+)(\.git)?\Z/

      tpl = uri.to_web_uri
      tpl.path += '/raw/$commit/$path'

      tpl.to_s
    end

    def relative_path(path)
      root = Pathname.new @repo.workdir
      file = Pathname.new path

      file.relative_path_from(root).to_s
    end

    def create_commit(message, files)
      old_index = @repo.index
      target = empty? ? nil : @repo.head.target

      if target
        old_index.read_tree target.tree
      else
        old_index.clear
      end

      new_index = @repo.index
      files.each {|f|
        if File.exist? f
          new_index.add relative_path(f)
        else
          new_index.remove relative_path(f)
        end
      }

      c = Rugged::Commit.create @repo, \
        tree: new_index.write_tree(@repo),
        message: message,
        parents: [target].compact,
        update_ref: 'HEAD'

      old_index.write

      # force-reload the repository
      @repo = Rugged::Repository.discover path

      get_commit c
    end

  private
    def fetch_commit(sha)
      if sha && sha.size.between?(7, 40) && @repo.include?(sha)
        object = @repo.lookup sha
        object if object.is_a? Rugged::Commit
      end
    rescue Rugged::InvalidError
      nil
    end
  end

  class Git::Commit
    def initialize(commit, repo)
      @commit, @repo = commit, repo
      @parent = commit.parents.first
    end

    def each_diff
      return enum_for :each_diff unless block_given?

      if @parent
        diff = @parent.diff id
      else
        diff = @commit.diff
      end

      diff.each_delta {|delta| yield Git::Diff.new(delta, @parent.nil?, @repo) }
    end

    def id
      @commit.oid
    end

    def short_id
      id[0...7]
    end

    def message
      @commit.message
    end

    def summary
      message.lines.first.chomp
    end

    def time
      @commit.time
    end

    def filelist
      lsfiles @commit.tree
    end

    def ==(o)
      id == o.id
    end

    def inspect
      "#<#{self.class} #{id} #{message}>"
    end

  private
    def lsfiles(tree, base = String.new)
      files = []

      tree.each {|obj|
        fullname = base.empty? ? obj[:name] : File.join(base, obj[:name])
        case obj[:type]
        when :blob
          files << fullname
        when :tree
          files.concat lsfiles(@repo.lookup(obj[:oid]), fullname)
        end
      }

      files
    end
  end

  class Git::Diff
    def initialize(delta, is_initial, repo)
      @delta, @repo = delta, repo

      if is_initial
        @status = :added
        @file = delta.old_file
      else
        @status = delta.status.to_sym
        @file = delta.new_file
      end
    end

    attr_reader :status

    def file
      @path ||= @file[:path].force_encoding(Encoding::UTF_8)
    end
    
    def new_content
      return if status == :deleted
      @new_content ||=
        @repo.lookup(@file[:oid]).content.force_encoding(Encoding::UTF_8)
    end

    def new_header
      @new_header ||= MetaHeader.new @new_content if new_content
    end
  end
end

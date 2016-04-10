require File.expand_path '../helper', __FILE__

class TestCLI < MiniTest::Test
  include CLIHelper

  def test_help
    assert_output /--help/, '' do
      i = ReaPack::Index::CLI.new ['--help']
      assert_equal true, i.run # does nothing
    end
  end

  def test_version
    assert_output /#{Regexp.escape ReaPack::Index::VERSION.to_s}/, '' do
      i = ReaPack::Index::CLI.new ['--version']
      assert_equal true, i.run # does nothing
    end
  end

  def test_help_version
    stdout, _ = capture_io do
      i = ReaPack::Index::CLI.new ['--help', '--version']
      assert_equal true, i.run # does nothing
    end

    refute_match ReaPack::Index::VERSION.to_s, stdout
  end

  def test_invalid_option
    assert_output '', /reapack-index: invalid option: --hello-world/i do
      i = ReaPack::Index::CLI.new ['--hello-world']
      assert_equal false, i.run
    end
  end

  def test_ambiguous_option
    assert_output '', /reapack-index: ambiguous option: --c/i do
      i = ReaPack::Index::CLI.new ['--c']
      assert_equal false, i.run
    end
  end

  def test_missing_argument
    assert_output nil, /missing argument/ do
      i = ReaPack::Index::CLI.new ['--output']
      assert_equal false, i.run # does nothing
    end
  end

  def test_output
    wrapper ['-o output.xml'] do
      @git.add mkfile('test.lua', '@version 1.0')
      @git.commit 'initial commit'

      capture_io do
        assert_equal true, @indexer.run
      end

      assert_match 'test.lua', read_index('output.xml')
    end
  end

  def test_multibyte_filename
    wrapper do
      script = mkfile("\342\200\224.lua")

      @git.add script
      @git.commit 'initial commit'

      @git.remove script
      @git.commit 'remove test'

      assert_output { @indexer.run }
    end
  end

  def test_invalid_unicode_sequence
    wrapper do
      @git.add mkfile('.gitkeep')
      @git.commit 'initial commit'

      @git.add mkfile('test.lua', "@version 1.0\n\n\x97")
      @git.commit 'second commit'

      assert_output { @indexer.run }
    end
  end

  def test_create_commit
    wrapper ['--commit'] do
      @git.add mkfile('.gitkeep')
      @git.commit 'initial commit'

      mkfile 'ignored1'
      @git.add mkfile('ignored2')

      assert_output("empty index\n", /commit created\n/) { @indexer.run }
      
      commit = @git.log(1).last
      assert_equal 'index: empty index', commit.message
      assert_equal ['index.xml'], commit.diff_parent.map {|d| d.path }
    end
  end

  def test_create_initial_commit
    wrapper ['--commit'] do
      mkfile 'ignored1'
      @git.add mkfile('ignored2')

      assert_output("empty index\n", /commit created\n/) { @indexer.run }

      commit = @git.log(1).last
      assert_equal 'index: empty index', commit.message
      assert_equal ['index.xml'], commit.gtree.files.keys
    end
  end

  def test_create_commit_accept
    wrapper ['--prompt-commit'] do
      @git.add mkfile('.gitkeep')
      @git.commit 'initial commit'

      fake_input do |fio|
        fio.getch = 'y'
        _, stderr = capture_io { @indexer.run }
        assert_match /commit created/i, stderr
      end

      commit = @git.log(1).last
      assert_equal 'index: empty index', commit.message
      assert_equal ['index.xml'], commit.diff_parent.map {|d| d.path }
    end
  end

  def test_create_commit_decline
    wrapper ['--prompt-commit'] do
      @git.add mkfile('.gitkeep')
      @git.commit 'initial commit'

      fake_input do |fio|
        fio.getch = 'n'
        _, stderr = capture_io { @indexer.run }
        refute_match /commit created/i, stderr
      end

      commit = @git.log(1).last
      refute_equal 'index: empty index', commit.message
      refute_equal ['index.xml'], commit.diff_parent.map {|d| d.path }
    end
  end

  def test_config
    assert_output /--help/, '' do
      wrapper [], setup: proc {
        mkfile '.reapack-index.conf', '--help'
      }
    end
  end

  def test_no_config
    stdout, _ = capture_io do
      wrapper ['--no-config'], setup: proc {
        mkfile '.reapack-index.conf', '--help'
      }
    end

    refute_match /--help/, stdout
  end

  def test_config_priority
    setup = proc {
      mkfile '.reapack-index.conf', "--verbose\n--no-warnings"
    }

    _, stderr = capture_io do
      wrapper ['--warnings'], setup: setup do
        @git.add mkfile('test.lua', 'no version tag in this script!')
        @git.commit 'initial commit'

        assert_equal true, @indexer.run
      end
    end

    assert_match /warning/i, stderr
    assert_match /verbose/i, stderr
  end

  def test_config_subdirectory
    wrapper do
      mkfile '.reapack-index.conf', '--help'
      mkfile 'Category/.gitkeep'

      Dir.chdir File.join(@git.dir.to_s, 'Category')

      assert_output /--help/ do
        ReaPack::Index::CLI.new
      end
    end
  end

  def test_working_directory_with_options
    wrapper do
      @git.add mkfile('README.md', '# Hello World')
      @git.commit 'initial commit'

      Dir.chdir @git.dir.to_s

      # no error = repository is found
      assert_output '', '' do
        i2 = ReaPack::Index::CLI.new ['--no-commit', '--quiet']
        i2.run
      end
    end
  end

  def test_no_such_repository
    no_such_file = if RUBY_PLATFORM =~ /mingw32/
      /cannot find the path specified/i
    else
      /no such file or directory/i
    end

    assert_output '', no_such_file do
      i = ReaPack::Index::CLI.new ['/hello/world']
      assert_equal false, i.run
    end

    assert_output '', /could not find repository/i do
      i = ReaPack::Index::CLI.new ['/']
      assert_equal false, i.run
    end
  end

  def test_progress
    wrapper ['--progress'] do
      @git.add mkfile('README.md', '# Hello World')
      @git.commit 'initial commit'

      stdout, stderr = capture_io do
        assert_equal true, @indexer.run
      end

      assert_equal "empty index\n", stdout
      assert_match "\rIndexing commit 1 of 1 (0%)..." \
        "\rIndexing commit 1 of 1 (100%)...\n", stderr
    end
  end

  def test_progress_no_new_commit
    setup = proc {
      @git.add mkfile('test1.lua', '@version 1.0')
      @git.commit 'initial commit'

      mkfile 'index.xml', <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" commit="#{@git.log(1).last.sha}"/>
      XML
    }

    wrapper ['--progress'], setup: setup do
      assert_output '', /Nothing to do!\n/ do
        @indexer.run
      end
    end
  end

  def test_progress_warnings
    wrapper ['--progress'] do
      @git.add mkfile('test.lua', 'no version tag in this script!')
      @git.commit 'initial commit'

      assert_output nil, /\nWarning:/i do
        assert_equal true, @indexer.run
      end
    end
  end

  def test_quiet_mode
    wrapper ['--verbose', '--progress', '--quiet'] do
      @git.add mkfile('test.lua', 'no version tag in this script!')
      @git.commit 'initial commit'

      assert_output '', '' do
        assert_equal true, @indexer.run
      end
    end
  end

  def test_no_git_remote
    wrapper [], remote: '*' do
      # no crash :)
      assert_output { @indexer.run }
    end
  end

  def test_weird_git_remote_url
    wrapper [], remote: 'scp://hello.world/$path' do
      _, stderr = capture_io { @indexer.run }
      refute_match /invalid url/i, stderr
      refute_match '$path', stderr
    end
  end

  def test_auto_url_template_ssh
    wrapper [], remote: 'git@github.com:User/Repo.git' do
      @git.add mkfile('hello.lua', '@version 1.0')
      @git.commit 'initial commit'

      assert_output { @indexer.run }
      assert_match "https://github.com/User/Repo/raw/#{@git.log(1).last.sha}/hello.lua", read_index
    end
  end

  def test_auto_url_template_https
    wrapper [], remote: 'https://github.com/User/Repo.git' do
      @git.add mkfile('hello.lua', '@version 1.0')
      @git.commit 'initial commit'

      assert_output { @indexer.run }
      assert_match "https://github.com/User/Repo/raw/#{@git.log(1).last.sha}/hello.lua", read_index
    end
  end

  def test_url_template
    wrapper ['--url-template=http://host/$path'], remote: false do
      @git.add mkfile('hello.lua', '@version 1.0')
      @git.commit 'initial commit'

      assert_output { @indexer.run }
      assert_match 'http://host/hello.lua', read_index
    end
  end

  def test_url_template_override_git
    wrapper ['--url-template=http://host/$path'] do
      @git.add mkfile('hello.lua', '@version 1.0')
      @git.commit 'initial commit'

      assert_output { @indexer.run }
      assert_match 'http://host/hello.lua', read_index
    end
  end

  def test_url_template_invalid
    wrapper ['--url-template=minoshiro'] do
      @git.add mkfile('hello.lua', '@version 1.0')
      @git.commit 'initial commit'

      _, stderr = capture_io { @indexer.run }
      assert_match /--url-template: .+\$path placeholder/i, stderr
    end
  end

  def test_scan_check_mutally_exclusive
    wrapper ['--check', '--scan'] do
      _, stderr = capture_io { @indexer.run }
      refute_match /finished checks/i, stderr
      read_index # index exists
    end

    wrapper ['--scan', '--check'] do
      _, stderr = capture_io { @indexer.run }
      assert_match /finished checks/i, stderr
      assert_raises(Errno::ENOENT) { read_index }
    end
  end
end

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
      @git.create_commit 'initial commit', [mkfile('test.lua', '@version 1.0')]

      capture_io do
        assert_equal true, @indexer.run
      end

      assert_match 'test.lua', read_index('output.xml')
    end
  end

  def test_create_commit
    wrapper ['--commit'] do
      assert_output("empty index\n", /commit created\n/) { @indexer.run }
      
      commit = @git.last_commit
      assert_equal 'index: empty index', commit.message
      assert_equal ['index.xml'], commit.each_diff.map {|d| d.file }
    end
  end

  def test_create_commit_accept
    wrapper ['--prompt-commit'] do
      @git.create_commit 'initial commit', [mkfile('.gitkeep')]

      fake_input do |fio|
        fio.getch = 'y'
        _, stderr = capture_io { @indexer.run }
        assert_match /commit created/i, stderr
      end

      commit = @git.last_commit
      assert_equal 'index: empty index', commit.message
      assert_equal ['index.xml'], commit.each_diff.map {|d| d.file }
    end
  end

  def test_create_commit_decline
    wrapper ['--prompt-commit'] do
      @git.create_commit 'initial commit', [mkfile('.gitkeep')]

      fake_input do |fio|
        fio.getch = 'n'
        _, stderr = capture_io { @indexer.run }
        refute_match /commit created/i, stderr
      end

      commit = @git.last_commit
      refute_equal 'index: empty index', commit.message
      refute_equal ['index.xml'], commit.each_diff.map {|d| d.file }
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
        @git.create_commit 'initial commit', [
          mkfile('test.lua', 'no version tag in this script!')
        ]

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

      Dir.chdir File.join(@git.path, 'Category')

      assert_output /--help/ do
        ReaPack::Index::CLI.new
      end
    end
  end

  def test_working_directory_with_options
    wrapper do
      @git.create_commit 'initial commit',
        [mkfile('README.md', '# Hello World')]

      Dir.chdir @git.path

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
      @git.create_commit 'initial commit',
        [mkfile('README.md', '# Hello World')]

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
      @git.create_commit 'initial commit',
        [mkfile('test1.lua', '@version 1.0')]

      mkfile 'index.xml', <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" commit="#{@git.last_commit.id}"/>
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
      @git.create_commit 'initial commit',
        [mkfile('test.lua', 'no version tag in this script!')]

      assert_output nil, /\nWarning:/i do
        assert_equal true, @indexer.run
      end
    end
  end

  def test_quiet_mode
    wrapper ['--verbose', '--progress', '--quiet'] do
      @git.create_commit 'initial commit',
        [mkfile('test.lua', 'no version tag in this script!')]

      assert_output '', '' do
        assert_equal true, @indexer.run
      end
    end
  end

  def test_no_git_remote
    wrapper [], remote: false do
      # no crash :)
      assert_output { @indexer.run }
    end
  end

  def test_url_template
    wrapper ['--url-template=http://host/$path'], remote: false do
      @git.create_commit 'initial commit',
        [mkfile('hello.lua', '@version 1.0')]

      assert_output { @indexer.run }
      assert_match 'http://host/hello.lua', read_index
    end
  end

  def test_url_template_override_git
    wrapper ['--url-template=http://host/$path'] do
      @git.create_commit 'initial commit',
        [mkfile('hello.lua', '@version 1.0')]

      assert_output { @indexer.run }
      assert_match 'http://host/hello.lua', read_index
    end
  end

  def test_url_template_invalid
    wrapper ['--url-template=minoshiro'] do
      @git.create_commit 'initial commit',
        [mkfile('hello.lua', '@version 1.0')]

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

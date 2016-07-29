require File.expand_path '../helper', __FILE__

class TestCLI < MiniTest::Test
  include CLIHelper

  def test_help
    assert_output /--help/, '' do
      assert_throws(:stop, true) { ReaPack::Index::CLI.new ['--help'] }
    end
  end

  def test_version
    assert_output /#{Regexp.escape ReaPack::Index::VERSION.to_s}/, '' do
      assert_throws(:stop, true) { ReaPack::Index::CLI.new ['--version'] }
    end
  end

  def test_help_version
    stdout, _ = capture_io do
      assert_throws(:stop, true) { ReaPack::Index::CLI.new ['--help', '--version'] }
    end

    refute_match ReaPack::Index::VERSION.to_s, stdout
  end

  def test_invalid_option
    assert_output '', /reapack-index: invalid option: --hello-world/i do
      assert_throws(:stop, false) { ReaPack::Index::CLI.new ['--hello-world'] }
    end
  end

  def test_ambiguous_option
    assert_output '', /reapack-index: ambiguous option: --c/i do
      assert_throws(:stop, false) { ReaPack::Index::CLI.new ['--c'] }
    end
  end

  def test_missing_argument
    assert_output nil, /missing argument/ do
      assert_throws(:stop, false) { ReaPack::Index::CLI.new ['--output'] }
    end
  end

  def test_output
    wrapper ['-o output.xml'] do
      assert_equal mkpath('output.xml'), @cli.index.path
    end
  end

  def test_create_commit
    wrapper ['--commit'] do
      assert_output("empty index\n", /commit created\n/) { @cli.run }
      
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
        _, stderr = capture_io { @cli.run }
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
        _, stderr = capture_io { @cli.run }
        refute_match /commit created/i, stderr
      end

      commit = @git.last_commit
      refute_equal 'index: empty index', commit.message
      refute_equal ['index.xml'], commit.each_diff.map {|d| d.file }
    end
  end

  def test_config
    catch :stop do
      assert_output /--help/, '' do
        wrapper [], setup: proc {
          mkfile '.reapack-index.conf', '--help'
        }
      end
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
          mkfile('cat/test.lua', 'no version tag in this script!')
        ]

        @cli.run
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
        catch :stop do ReaPack::Index::CLI.new end
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
      assert_throws(:stop, false) { ReaPack::Index::CLI.new ['/hello/world'] }
    end

    assert_output '', /could not find repository/i do
      assert_throws(:stop, false) { ReaPack::Index::CLI.new ['/'] }
    end
  end

  def test_invalid_index
    assert_output '', /\A'.+index\.xml' is not a ReaPack index file\Z/ do
      setup = proc { mkfile 'index.xml', "\0" }
      assert_throws(:stop, false) { wrapper [], setup: setup do end }
    end
  end

  def test_progress
    wrapper ['--progress'] do
      @git.create_commit 'initial commit',
        [mkfile('README.md', '# Hello World')]

      stdout, stderr = capture_io do
        @cli.run
      end

      assert_equal "empty index\n", stdout
      assert_match "\rIndexing commit 1 of 1 (0%)..." \
        "\rIndexing commit 1 of 1 (100%)...\n", stderr
    end
  end

  def test_progress_no_new_commit
    setup = proc {
      @git.create_commit 'initial commit',
        [mkfile('cat/test1.lua', '@version 1.0')]

      mkfile 'index.xml', <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" commit="#{@git.last_commit.id}"/>
      XML
    }

    wrapper ['--progress'], setup: setup do
      assert_output '', /nothing to do/i do
        @cli.run
      end
    end
  end

  def test_progress_warnings
    wrapper ['--progress'] do
      @git.create_commit 'initial commit',
        [mkfile('cat/test.lua', 'no version tag in this script!')]

      # must output a new line before 'warning:'
      assert_output(nil, /\nwarning:/i) { @cli.run }
    end
  end

  def test_quiet_mode
    wrapper ['--verbose', '--progress', '--quiet'] do
      @git.create_commit 'initial commit',
        [mkfile('cat/test.lua', 'no version tag in this script!')]

      assert_output('', '') { @cli.run }
    end
  end

  def test_url_template
    assert_output '', '' do
      wrapper ['--url-template=http://host/$path'], remote: false do
        assert_equal 'http://host/$path', @cli.index.url_template
      end
    end
  end

  def test_url_template_override_vcs
    assert_output '', '' do
      wrapper ['--url-template=http://host/$path'] do
        assert_equal 'http://host/$path', @cli.index.url_template
      end
    end
  end

  def test_url_template_invalid
    _, stderr = capture_io do
      wrapper ['--url-template=minoshiro'] do
        assert_nil @cli.index.url_template
      end
    end

    assert_match /--url-template: .+\$path placeholder/i, stderr
  end

  def test_scan_check_mutally_exclusive
    wrapper ['--check', '--scan'] do
      _, stderr = capture_io { @cli.run }
      refute_match /finished checks/i, stderr
      read_index # index exists
    end

    wrapper ['--scan', '--check'] do
      _, stderr = capture_io { @cli.run }
      assert_match /finished checks/i, stderr
      assert_raises(Errno::ENOENT) { read_index }
    end

    wrapper ['--check', '--rebuild'] do
      _, stderr = capture_io { @cli.run }
      refute_match /finished checks/i, stderr
      read_index # index exists
    end
  end
end

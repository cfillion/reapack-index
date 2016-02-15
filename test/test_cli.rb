require File.expand_path '../helper', __FILE__

require 'git'

module CLIUtils
  class FakeIO
    def initialize
      @getch = 'n'
    end

    attr_accessor :getch
  end

  def fake_input
    stdin = $stdin
    $stdin = FakeIO.new

    yield $stdin
  ensure
    $stdin = stdin
  end

  def wrapper(args = [], options = {})
    Dir.mktmpdir('test-repository') do |path|
      @git = Git.init path
      @git.config('user.name', 'John Doe')
      @git.config('user.email', 'john@doe.com')

      if options[:remote] != false
        @git.add_remote 'origin', 'git@github.com:cfillion/test-repository.git'
      end

      options[:setup].call if options.has_key? :setup

      @indexer = ReaPack::Index::CLI.new \
        ['--no-progress', '--no-commit'] + args + ['--', path]

      yield if block_given?
    end
  ensure
    @git = @indexer = nil
  end

  def mkfile(file, content = String.new)
    fn = File.join @git.dir.to_s, file
    FileUtils.mkdir_p File.dirname(fn)
    File.write fn, content
    fn
  end

  def read_index(file = 'index.xml')
    File.read File.expand_path(file, @git.dir.to_s)
  end
end

class TestCLI < MiniTest::Test
  include CLIUtils

  def teardown
    # who is changing the working directory without restoring it?!
    Dir.chdir File.dirname(__FILE__)
  end

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

  def test_invalid_option
    assert_output '', /reapack-indexer: invalid option: --hello-world/i do
      i = ReaPack::Index::CLI.new ['--hello-world']
      assert_equal false, i.run # does nothing
    end
  end

  def test_empty_branch
    wrapper do
      assert_output nil, /the current branch does not contains any commit/i do
        assert_equal true, @indexer.run
      end
    end
  end

  def test_initial_commit
    wrapper do
      @git.add mkfile('test1.lua', '@version 1.0')
      @git.add mkfile('Category/test2.lua', '@version 1.0')
      @git.add mkfile('Category/Sub/test3.lua', '@version 1.0')
      @git.commit 'initial commit'

      assert_output /3 new packages/, '' do
        assert_equal true, @indexer.run
      end

      assert_match 'Category/test2.lua', read_index
      assert_match "raw/#{@git.log(1).last.sha}/test1.lua", read_index

      assert_match @git.log(1).last.date.utc.iso8601, read_index
    end
  end

  def test_normal_commit
    wrapper do
      @git.add mkfile('README.md', '# Hello World')
      @git.commit 'initial commit'

      @git.add mkfile('test1.lua', '@version 1.0')
      @git.add mkfile('Category/test2.lua', '@version 1.0')
      @git.add mkfile('Category/Sub/test3.lua', '@version 1.0')
      @git.commit 'second commit'

      assert_output "3 new categories, 3 new packages, 3 new versions\n", '' do
        assert_equal true, @indexer.run
      end

      assert_match 'Category/test2.lua', read_index
    end
  end

  def test_pwd_is_subdirectory
    wrapper do
      @git.add mkfile('test1.lua', '@version 1.0')
      @git.commit 'initial commit'

      pwd = File.join(@git.dir.to_s, 'test')
      Dir.mkdir pwd
      Dir.chdir pwd

      assert_output /1 new package/, '' do
        assert_equal true, @indexer.run
      end

      assert_match 'test1.lua', read_index
    end
  end

  def test_verbose
    stdout, stderr = capture_io do
      wrapper ['--verbose'] do
        @git.add mkfile('test.lua', '@version 1.0')
        @git.add mkfile('test.png')
        @git.commit 'initial commit'

        assert_equal true, @indexer.run
      end
    end

    assert_equal "1 new category, 1 new package, 1 new version\n", stdout
    assert_match /reading configuration from .+\.reapack-index\.conf/i, stderr
    assert_match /processing [a-f0-9]{7}: initial commit/i, stderr
    assert_match /indexing new file test.lua/, stderr
    refute_match /indexing new file test.png/, stderr
  end

  def test_verbose_override
    wrapper ['--verbose', '--no-verbose'] do
      @git.add mkfile('README.md', '# Hello World')
      @git.commit 'initial commit'

      stdout, stderr = capture_io do
        assert_equal true, @indexer.run
      end

      assert_equal "empty index\n", stdout
      refute_match /processing [a-f0-9]{7}: initial commit/i, stderr
    end
  end

  def test_invalid_metadata
    wrapper do
      @git.add mkfile('test.lua', 'no version tag in this script!')
      @git.commit 'initial commit'

      assert_output nil, /Warning: test\.lua: Invalid metadata/i do
        assert_equal true, @indexer.run
      end
    end
  end

  def test_no_warnings
    wrapper ['-w'] do
      @git.add mkfile('test.lua', 'no version tag in this script!')
      @git.commit 'initial commit'

      stdout, stderr = capture_io do
        assert_equal true, @indexer.run
      end

      refute_match /Warning: test\.lua: Invalid metadata/i, stderr
    end
  end

  def test_no_warnings_override
    wrapper ['-w', '-W'] do
      @git.add mkfile('test.lua', 'no version tag in this script!')
      @git.commit 'initial commit'

      assert_output nil, /Warning: test\.lua: Invalid metadata/i do
        assert_equal true, @indexer.run
      end
    end
  end

  def test_index_from_last
    setup = proc {
      @git.add mkfile('test1.lua', '@version 1.0')
      @git.commit 'initial commit'
      
      mkfile 'index.xml', <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" commit="#{@git.log(1).last.sha}"/>
      XML
    }

    wrapper [], setup: setup do
      # next line ensures only files in this commit are scanned
      mkfile('test1.lua', '@version 1.1')

      @git.add mkfile('test2.lua', '@version 1.0')
      @git.commit 'second commit'

      assert_output nil, '' do
        assert_equal true, @indexer.run
      end

      refute_match 'test1.lua', read_index
      assert_match 'test2.lua', read_index
    end
  end

  def test_no_amend
    setup = proc {
      @git.add mkfile('Test/test.lua', '@version 1.0')
      @git.commit 'initial commit'
      
      mkfile 'index.xml', <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" commit="#{@git.log(1).last.sha}">
  <category name="Test">
    <reapack name="test.lua" type="script">
      <version name="1.0"/>
    </reapack>
  </category>
</index>
      XML
    }

    wrapper ['--no-amend'], setup: setup do
      @git.add mkfile('Test/test.lua', "@version 1.0\n@author cfillion")
      @git.commit 'second commit'

      assert_output '', /nothing to do/i do
        assert_equal true, @indexer.run
      end

      refute_match 'cfillion', read_index
    end
  end

  def test_amend
    setup = proc {
      @git.add mkfile('Test/test.lua', '@version 1.0')
      @git.commit 'initial commit'
      
      mkfile 'index.xml', <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" commit="#{@git.log(1).last.sha}">
  <category name="Test">
    <reapack name="test.lua" type="script">
      <version name="1.0"/>
    </reapack>
  </category>
</index>
      XML
    }

    wrapper ['--amend'], setup: setup do
      @git.add mkfile('Test/test.lua', "@version 1.0\n@author cfillion")
      @git.commit 'second commit'

      assert_output /1 modified package/i, '' do
        assert_equal true, @indexer.run
      end

      assert_match 'cfillion', read_index
    end
  end

  def test_remove
    wrapper do
      script = mkfile 'test.lua', '@version 1.0'

      @git.add script
      @git.commit 'initial commit'

      @git.remove script
      @git.commit 'second commit'

      assert_output /1 removed package/i, '' do
        assert_equal true, @indexer.run
      end

      refute_match 'test.lua', read_index
    end
  end

  def test_output
    wrapper ['-o output.xml'] do
      @git.add mkfile('test.lua', '@version 1.0')
      @git.commit 'initial commit'

      assert_output nil, '' do
        assert_equal true, @indexer.run
      end

      assert_match 'test.lua', read_index('output.xml')
    end
  end

  def test_missing_argument
    assert_output nil, /missing argument/ do
      i = ReaPack::Index::CLI.new ['--output']
      assert_equal false, i.run # does nothing
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

      assert_output("empty index\n", "commit created\n") { @indexer.run }
      
      commit = @git.log(1).last
      assert_equal 'index: empty index', commit.message
      assert_equal ['index.xml'], commit.diff_parent.map {|d| d.path }
    end
  end

  def test_create_commit_accept
    wrapper ['--prompt-commit'] do
      @git.add mkfile('.gitkeep')
      @git.commit 'initial commit'

      fake_input do |fio|
        fio.getch = 'y'
        stdin, stderr = capture_io { @indexer.run }
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
        stdin, stderr = capture_io { @indexer.run }
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
    stdout, stderr = capture_io do
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

    stdout, stderr = capture_io do
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
    pwd = Dir.pwd

    wrapper do
      mkfile '.reapack-index.conf', '--help'
      mkfile 'Category/.gitkeep'

      Dir.chdir File.join(@git.dir.to_s, 'Category')

      assert_output /--help/ do
        ReaPack::Index::CLI.new
      end
    end
  ensure
    Dir.chdir pwd
  end

  def test_working_directory_with_options
    wrapper do
      @git.add mkfile('README.md', '# Hello World')
      @git.commit 'initial commit'

      begin
        pwd = Dir.pwd
        Dir.chdir @git.dir.to_s

        assert_output '', '' do
          i2 = ReaPack::Index::CLI.new ['--no-commit', '--quiet']
          i2.run
        end
      ensure
        Dir.chdir pwd
      end
    end
  end

  def test_no_such_repository
    assert_output '', /no such file or directory/i do
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
      assert_output '', "Nothing to do!\n" do
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

  def test_website_link
    wrapper ['-l http://cfillion.tk'] do
      assert_output "1 new website link, empty index\n", '' do
        assert_equal true, @indexer.run
      end

      assert_match 'rel="website">http://cfillion.tk</link>', read_index
    end
  end

  def test_website_link
    wrapper ['--donation-link', 'Link Label=http://cfillion.tk'] do
      assert_output "1 new donation link, empty index\n" do
        assert_equal true, @indexer.run
      end

      assert_match 'rel="donation" href="http://cfillion.tk">Link Label</link>',
        read_index
    end
  end

  def test_invalid_link
    wrapper ['--link', 'shinsekai yori', '--link', 'http://cfillion.tk'] do
      assert_output "1 new website link, empty index\n",
          /warning: invalid url: shinsekai yori/i do
        assert_equal true, @indexer.run
      end

      assert_match 'rel="website">http://cfillion.tk</link>', read_index
    end
  end

  def test_remove_link
    wrapper ['--link', 'http://test.com', '--link', '-http://test.com'] do
      assert_output "1 new website link, 1 removed website link, empty index\n" do
        assert_equal true, @indexer.run
      end

      refute_match 'rel="website">http://test.com</link>', read_index
    end
  end

  def test_list_links
    setup = proc {
      mkfile 'index.xml', <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1">
  <metadata>
    <link rel="website" href="http://anidb.net/a9002">Shinsekai Yori</link>
    <link rel="donation" href="http://paypal.com">Donate!</link>
    <link rel="website">http://cfillion.tk</link>
      XML
    }

    wrapper ['--ls-links'], setup: setup do
      stdin, stderr = capture_io do
        assert_equal true, @indexer.run
      end

      expected = <<-OUT
[website] Shinsekai Yori (http://anidb.net/a9002)
[website] http://cfillion.tk
[donation] Donate! (http://paypal.com)
      OUT

      assert_equal expected, stdin
      assert_empty stderr
    end
  end

  def test_no_git_remote
    wrapper [], remote: false do
      assert_output { @indexer.run }
    end
  end

  def test_about
    opts = ['--about']

    setup = proc {
      opts << mkfile('README.md', '# Hello World')
    }

    wrapper opts, setup: setup do
      assert_output "1 modified metadata, empty index\n" do
        assert_equal true, @indexer.run
      end

      assert_match 'Hello World', read_index
    end
  end

  def test_about_file_not_found
    # 404.md is read in the working directory
    wrapper ['--about=404.md'] do
      assert_output "empty index\n",
          /warning: --about: no such file or directory - 404.md/i do
        assert_equal true, @indexer.run
      end
    end
  end

  def test_about_pandoc_not_found
    old_path = ENV['PATH']

    opts = ['--about']

    setup = proc {
      opts << mkfile('README.md', '# Hello World')
    }

    wrapper opts, setup: setup do
      assert_output "empty index\n", /pandoc executable cannot be found/i do
        ENV['PATH'] = String.new
        assert_equal true, @indexer.run
      end
    end
  ensure
    ENV['PATH'] = old_path
  end

  def test_about_clear
    setup = proc {
      mkfile 'index.xml', <<-XML
<index>
  <metadata>
    <description><![CDATA[Hello World]]></description>
  </metadata>
</index>
      XML
    }

    wrapper ['--remove-about'], setup: setup do
      assert_output "1 modified metadata\n" do
        assert_equal true, @indexer.run
      end

      refute_match 'Hello World', read_index
    end
  end

  def test_about_dump
    setup = proc {
      mkfile 'index.xml', <<-XML
<index>
  <metadata>
    <description><![CDATA[Hello World]]></description>
  </metadata>
</index>
      XML
    }

    wrapper ['--dump-about'], setup: setup do
      assert_output 'Hello World' do
        assert_equal true, @indexer.run
      end
    end
  end

  def test_check_pass
    expected = <<-STDERR
..

Finished checks for 2 packages with 0 failures
    STDERR

    wrapper ['--check'] do
      mkfile 'test1.lua', '@version 1.0'
      mkfile 'test2.lua', '@version 1.0'

      assert_output nil, expected do
        assert_equal true, @indexer.run
      end
    end
  end

  def test_check_failure
    expected = <<-STDERR
F.

test1.lua contains invalid metadata:
  - missing tag "version"
  - invalid value for tag "author"

Finished checks for 2 packages with 1 failure
    STDERR

    wrapper ['--check'] do
      mkfile 'test1.lua', '@author'
      mkfile 'test2.lua', '@version 1.0'

      assert_output nil, expected do
        assert_equal false, @indexer.run
      end
    end
  end

  def test_check_quiet
    expected = <<-STDERR
test1.lua contains invalid metadata:
  - missing tag "version"
  - invalid value for tag "author"

test2.lua contains invalid metadata:
  - missing tag "version"
    STDERR

    wrapper ['--check', '--quiet'] do
      mkfile 'test1.lua', '@author'
      mkfile 'test2.lua'
      mkfile 'test3.lua', '@version 1.0'

      assert_output nil, expected do
        assert_equal false, @indexer.run
      end
    end
  end
end

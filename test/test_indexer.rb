require File.expand_path '../helper', __FILE__

module IndexerUtils
  class FakeIO
    def initialize
      @getch = 'n'
    end

    attr_accessor :getch
  end

  def wrapper(options = [], setup = nil)
    stdin = $stdin
    $stdin = FakeIO.new

    Dir.mktmpdir('test-repository') do |path|
      @git = Git.init path
      @git.add_remote 'origin', 'git@github.com:cfillion/test-repository.git'
      @git.config('user.name', 'John Doe')
      @git.config('user.email', 'john@doe.com')

      setup[] if setup

      @indexer = ReaPack::Index::Indexer.new \
        ['--no-progress', '--no-commit'] + options + ['--', path]

      yield if block_given?
    end
  ensure
    $stdin = stdin
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

class TestIndexer < MiniTest::Test
  include IndexerUtils

  def teardown
    # who is changing the working directory without restoring it?!
    Dir.chdir File.dirname(__FILE__)
  end

  def test_help
    assert_output /--help/, '' do
      i = ReaPack::Index::Indexer.new ['--help']
      assert_equal true, i.run # does nothing
    end
  end

  def test_version
    assert_output /#{Regexp.escape ReaPack::Index::VERSION.to_s}/, '' do
      i = ReaPack::Index::Indexer.new ['--version']
      assert_equal true, i.run # does nothing
    end
  end

  def test_invalid_option
    assert_output '', "reapack-indexer: invalid option: --hello-world\n" do
      i = ReaPack::Index::Indexer.new ['--hello-world']
      assert_equal false, i.run # does nothing
    end
  end

  def test_empty_branch
    wrapper do
      assert_output '', /current branch is empty/i do
        assert_equal false, @indexer.run
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
    wrapper ['--verbose'] do
      @git.add mkfile('test.lua', '@version 1.0')
      @git.add mkfile('test.png')
      @git.commit 'initial commit'

      stdout, stderr = capture_io do
        assert_equal true, @indexer.run
      end

      assert_equal "1 new category, 1 new package, 1 new version\n", stdout
      assert_match /Processing [a-f0-9]{7}: initial commit/, stderr
      assert_match /indexing new file test.lua/, stderr
      refute_match /indexing new file test.png/, stderr
    end
  end

  def test_verbose_override
    wrapper ['--verbose', '--no-verbose'] do
      @git.add mkfile('README.md', '# Hello World')
      @git.commit 'initial commit'

      stdout, stderr = capture_io do
        assert_equal true, @indexer.run
      end

      assert_equal "empty index\n", stdout
      refute_match /Processing [a-f0-9]{7}: initial commit/, stderr
    end
  end

  def test_invalid_metadata
    wrapper do
      @git.add mkfile('test.lua', 'no version tag in this script!')
      @git.commit 'initial commit'

      assert_output nil, /Warning: Invalid metadata/ do
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

      refute_match /Warning: Invalid metadata/i, stderr
    end
  end

  def test_no_warnings_override
    wrapper ['-w', '-W'] do
      @git.add mkfile('test.lua', 'no version tag in this script!')
      @git.commit 'initial commit'

      assert_output nil, /Warning: Invalid metadata/ do
        assert_equal true, @indexer.run
      end
    end
  end

  def test_index_from_last
    setup = proc {
      @git.add mkfile('test1.lua', '@version 1.0')
      @git.commit 'initial commit'
      
      index = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" commit="#{@git.log(1).last.sha}"/>
      XML

      mkfile 'index.xml', index
    }

    wrapper [], setup do
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
      
      index = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" commit="#{@git.log(1).last.sha}">
  <category name="Test">
    <reapack name="test.lua" type="script">
      <version name="1.0"/>
    </reapack>
  </category>
</index>
      XML

      mkfile 'index.xml', index
    }

    wrapper ['--no-amend'], setup do
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
      
      index = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" commit="#{@git.log(1).last.sha}">
  <category name="Test">
    <reapack name="test.lua" type="script">
      <version name="1.0"/>
    </reapack>
  </category>
</index>
      XML

      mkfile 'index.xml', index
    }

    wrapper ['--amend'], setup do
      @git.add mkfile('Test/test.lua', "@version 1.0\n@author cfillion")
      @git.commit 'second commit'

      assert_output /1 modified package/i, '' do
        assert_equal true, @indexer.run
      end

      assert_match 'cfillion', read_index
    end
  end

  def test_warn_branch
    wrapper do
      @git.add mkfile('README.md', '# Hello World')
      @git.commit 'initial commit'

      @git.branch('new-branch').checkout

      assert_output '', /branch new-branch is not/ do
        assert_equal false, @indexer.run
      end
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
      i = ReaPack::Index::Indexer.new ['--output']
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

  def test_commit
    wrapper ['--commit'] do
      @git.add mkfile('.gitkeep')
      @git.commit 'initial commit'

      assert_output("empty index\n", "commit created\n") { @indexer.run }
      
      commit = @git.log(1).last
      assert_equal 'index: empty index', commit.message
      assert_equal ['index.xml'], commit.diff_parent.map {|d| d.path }
    end
  end

  def test_config
    setup = proc {
      mkfile '.reapack-index.conf', '--help'
    }

    assert_output /--help/, '' do
      wrapper [], setup
    end
  end

  def test_config_priority
    setup = proc {
      mkfile '.reapack-index.conf', '--no-warnings'
    }

    wrapper ['--warnings'], setup do
      @git.add mkfile('test.lua', 'no version tag in this script!')
      @git.commit 'initial commit'

      assert_output nil, /warning/i do
        assert_equal true, @indexer.run
      end
    end
  end

  def test_config_subdirectory
    pwd = Dir.pwd

    wrapper do
      mkfile '.reapack-index.conf', '--help'
      mkfile 'Category/.gitkeep'

      Dir.chdir File.join(@git.dir.to_s, 'Category')

      assert_output /--help/ do
        ReaPack::Index::Indexer.new
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
          i2 = ReaPack::Index::Indexer.new ['--no-commit', '--quiet']
          i2.run
        end
      ensure
        Dir.chdir pwd
      end
    end
  end

  def test_no_such_repository
    assert_output '', /no such file or directory/i do
      i = ReaPack::Index::Indexer.new ['/hello/world']
      assert_equal false, i.run
    end

    assert_output '', /could not find repository/i do
      i = ReaPack::Index::Indexer.new ['/']
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

      index = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" commit="#{@git.log(1).last.sha}"/>
      XML

      mkfile 'index.xml', index
    }

    wrapper ['--progress'], setup do
      assert_output '', "Nothing to do!\n" do
        @indexer.run
      end
    end
  end

  def test_progress_warnings
    wrapper ['--progress'] do
      @git.add mkfile('test.lua', 'no version tag in this script!')
      @git.commit 'initial commit'

      assert_output nil, /\nWarning:/ do
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
end
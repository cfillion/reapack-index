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

      @indexer = ReaPack::Index::Indexer.new options + ['--', path]

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

      assert_output /3 new packages/, '' do
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

      assert_match /Processing [a-f0-9]{7}: initial commit/, stdout
      assert_match /indexing new file test.lua/, stdout
      refute_match /indexing new file test.png/, stdout
      assert_empty stderr
    end
  end

  def test_verbose_override
    wrapper ['--verbose', '--no-verbose'] do
      @git.add mkfile('README.md', '# Hello World')
      @git.commit 'initial commit'

      stdout, stderr = capture_io do
        assert_equal true, @indexer.run
      end

      refute_match /initial commit/, stdout
      assert_empty stderr
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

    wrapper do
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

      assert_output /nothing to do/i, '' do
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

      assert_output /branch new-branch is not/, '' do
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
    wrapper do
      $stdin.getch = 'y'

      @git.add mkfile('.gitkeep')
      @git.commit 'initial commit'

      assert_output(/done/, '') { @indexer.run }
      
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
end

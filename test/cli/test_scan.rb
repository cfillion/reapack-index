require File.expand_path '../../helper', __FILE__

TestCLI ||= Class.new MiniTest::Test

class TestCLI::Scan < MiniTest::Test
  include CLIHelper

  def test_initial_commit
    wrapper do
      @git.create_commit 'initial commit', [
        mkfile('test1.lua', '@version 1.0'),
        mkfile('Category/test2.lua', '@version 1.0'),
        mkfile('Category/Sub/test3.lua', '@version 1.0'),
      ]

      assert_output /3 new packages/ do
        assert_equal true, @indexer.run
      end

      assert_match 'Category/test2.lua', read_index
      assert_match "raw/#{@git.last_commit.id}/test1.lua", read_index
      assert_match 'https://github.com/cfillion/test-repository/raw', read_index

      assert_match @git.last_commit.time.utc.iso8601, read_index
    end
  end

  def test_normal_commit
    wrapper do
      @git.create_commit 'initial commit',
        [mkfile('README.md', '# Hello World')]

      @git.create_commit 'second commit', [
        mkfile('test1.lua', '@version 1.0'),
        mkfile('Category/test2.lua', '@version 1.0'),
        mkfile('Category/Sub/test3.lua', '@version 1.0'),
      ]

      assert_output "3 new categories, 3 new packages, 3 new versions\n" do
        assert_equal true, @indexer.run
      end

      assert_match 'Category/test2.lua', read_index
    end
  end

  def test_empty_branch
    wrapper do
      assert_output nil, /the current branch does not contains any commit/i do
        assert_equal true, @indexer.run
      end
    end
  end

  def test_pwd_is_subdirectory
    wrapper do
      @git.create_commit 'initial commit', [mkfile('test1.lua', '@version 1.0')]

      pwd = File.join(@git.path, 'test')
      Dir.mkdir pwd
      Dir.chdir pwd

      assert_output /1 new package/ do
        assert_equal true, @indexer.run
      end

      assert_match 'test1.lua', read_index
    end
  end

  def test_verbose
    stdout, stderr = capture_io do
      wrapper ['--verbose'] do
        script = mkfile 'test.lua', '@version 1.0'
        @git.create_commit 'initial commit', [
          script,
          mkfile('test.png', 'file not shown in output'),
        ]

        @git.create_commit 'second commit', [
          mkfile('test.lua', '@version 2.0'),
          mkfile('test.jsfx', '@version 1.0'),
        ]

        File.delete script
        @git.create_commit 'third commit', [script]

        assert_equal true, @indexer.run
      end
    end

    assert_match /reading configuration from .+\.reapack-index\.conf/, stderr

    verbose = /
processing [a-f0-9]{7}: initial commit
-> indexing added file test\.lua
processing [a-f0-9]{7}: second commit
-> indexing added file test\.jsfx
-> indexing modified file test\.lua
processing [a-f0-9]{7}: third commit
-> indexing deleted file test\.lua/i

    assert_match verbose, stderr
  end

  def test_verbose_override
    wrapper ['--verbose', '--no-verbose'] do
      @git.create_commit 'initial commit', [mkfile('README.md', '# Hello World')]

      stdout, stderr = capture_io do
        assert_equal true, @indexer.run
      end

      assert_equal "empty index\n", stdout
      refute_match /processing [a-f0-9]{7}: initial commit/i, stderr
    end
  end

  def test_invalid_metadata
    wrapper do
      @git.create_commit 'initial commit',
        [mkfile('test.lua', 'no version tag in this script!')]

      assert_output nil, /Warning: test\.lua: Invalid metadata/i do
        assert_equal true, @indexer.run
      end
    end
  end

  def test_no_warnings
    wrapper ['-w'] do
      @git.create_commit 'initial commit',
        [mkfile('test.lua', 'no version tag in this script!')]

      _, stderr = capture_io do
        assert_equal true, @indexer.run
      end

      refute_match /Warning: test\.lua: Invalid metadata/i, stderr
    end
  end

  def test_no_warnings_override
    wrapper ['-w', '-W'] do
      @git.create_commit 'initial commit',
        [mkfile('test.lua', 'no version tag in this script!')]

      assert_output nil, /Warning: test\.lua: Invalid metadata/i do
        assert_equal true, @indexer.run
      end
    end
  end

  def test_from_last
    setup = proc {
      @git.create_commit 'initial commit', [mkfile('test1.lua', '@version 1.0')]

      mkfile 'index.xml', <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" name="hello" commit="#{@git.last_commit.id}"/>
      XML
    }

    wrapper [], setup: setup do
      @git.create_commit 'second commit', [mkfile('test2.lua', '@version 1.0')]

      assert_output nil, '' do
        assert_equal true, @indexer.run
      end

      refute_match 'test1.lua', read_index
      assert_match 'test2.lua', read_index
    end
  end

  def test_amend
    setup = proc {
      @git.create_commit 'initial commit',
        [mkfile('Test/test.lua', '@version 1.0')]
      
      mkfile 'index.xml', <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" name="hello" commit="#{@git.last_commit.id}">
  <category name="Test">
    <reapack name="test.lua" type="script">
      <version name="1.0"/>
    </reapack>
  </category>
</index>
      XML
    }

    wrapper ['--amend'], setup: setup do
      @git.create_commit 'second commit',
        [mkfile('Test/test.lua', "@version 1.0\n@author cfillion")]

      assert_output /1 modified package/i, '' do
        assert_equal true, @indexer.run
      end

      assert_match 'cfillion', read_index
    end
  end

  def test_no_amend
    setup = proc {
      @git.create_commit 'initial commit',
        [mkfile('Test/test.lua', '@version 1.0')]
      
      mkfile 'index.xml', <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" commit="#{@git.last_commit.id}">
  <category name="Test">
    <reapack name="test.lua" type="script">
      <version name="1.0"/>
    </reapack>
  </category>
</index>
      XML
    }

    wrapper ['--no-amend'], setup: setup do
      @git.create_commit 'second commit',
        [mkfile('Test/test.lua', "@version 1.0\n@author cfillion")]

      assert_output '', /nothing to do/i do
        assert_equal true, @indexer.run
      end

      refute_match 'cfillion', read_index
    end
  end

  def test_scan_ignore
    setup = proc { Dir.chdir @git.path }

    wrapper ['--ignore=Hello', '--ignore=Chunky/Bacon.lua',
             '--ignore=test2.lua'], setup: setup do
      @git.create_commit 'initial commit', [
        mkfile('Hello/World.lua', 'konnichiwa'),
        mkfile('Chunky/Bacon.lua', 'konnichiwa'),
        mkfile('Directory/test2.lua', '@version 1.0'),
      ]

      assert_output "1 new category, 1 new package, 1 new version\n" do
        assert_equal true, @indexer.run
      end

      refute_match 'Hello/World.lua', read_index
      refute_match 'Chunky/Bacon.lua', read_index
      assert_match 'Directory/test2.lua', read_index
    end
  end

  def test_remove
    wrapper do
      script = mkfile 'test.lua', '@version 1.0'

      @git.create_commit 'initial commit', [script]

      File.delete script
      @git.create_commit 'second commit', [script]

      assert_output /1 removed package/i do
        assert_equal true, @indexer.run
      end

      refute_match 'test.lua', read_index
    end
  end

  def test_specify_commit
    # --progress to check for FloatDomainError: Infinity errors
    options = ['--progress', '--scan']

    setup = proc {
      @git.create_commit 'initial commit',
        [mkfile('test1.lua', '@version 2.0')]

      @git.create_commit 'second commit',
        [mkfile('test2.lua', '@version 1.0')]
      options << @git.last_commit.id

      @git.create_commit 'third commit',
        [mkfile('test3.lua', '@version 1.1')]
    }

    wrapper options, setup: setup do
      capture_io { assert_equal true, @indexer.run }

      refute_match 'test1.lua', read_index, 'The initial commit was scanned'
      assert_match 'test2.lua', read_index
      refute_match 'test3.lua', read_index, 'The third commit was scanned'
    end
  end

  def test_specify_two_commits
    options = ['--scan', nil, '--scan', nil]

    setup = proc {
      @git.create_commit 'initial commit',
        [mkfile('test1.lua', '@version 2.0')]

      @git.create_commit 'second commit',
        [mkfile('test2.lua', '@version 1.0')]
      options[1] = @git.last_commit.id

      @git.create_commit 'third commit',
        [mkfile('test3.lua', '@version 1.1')]
      options[3] = @git.last_commit.id
    }

    wrapper options, setup: setup do
      capture_io { assert_equal true, @indexer.run }

      refute_match 'test1.lua', read_index, 'The initial commit was scanned'
      assert_match 'test2.lua', read_index
      assert_match 'test3.lua', read_index
    end
  end

  def test_reset
    options = ['--scan']

    setup = proc {
      @git.create_commit 'initial commit',
        [mkfile('test1.lua', '@version 2.0')]

      @git.create_commit 'second commit',
        [mkfile('test2.lua', '@version 1.0')]
      options << @git.last_commit.id

      options << '--scan'
    }

    wrapper options, setup: setup do
      capture_io { assert_equal true, @indexer.run }
      assert_match 'test1.lua', read_index
    end
  end

  def test_short_hash
    options = ['--scan']

    setup = proc {
      @git.create_commit 'initial commit',
        [mkfile('test1.lua', '@version 2.0')]
      options << @git.last_commit.short_id
    }

    wrapper options, setup: setup do
      capture_io { assert_equal true, @indexer.run }
    end
  end

  def test_invalid_hashes
    INVALID_HASHES.each {|hash|
      wrapper ['--scan', hash] do
        @git.create_commit 'initial commit', [mkfile('README.md')]

        assert_output nil, /--scan: bad revision: #{Regexp.escape hash}/i do
          assert_equal false, @indexer.run
        end
      end
    }
  end

  def test_no_arguments
    wrapper ['--scan'] do; end
  end
end

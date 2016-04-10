require File.expand_path '../../helper', __FILE__

TestCLI ||= Class.new MiniTest::Test

class TestCLI::Scan < MiniTest::Test
  include CLIHelper

  def test_initial_commit
    wrapper do
      @git.add mkfile('test1.lua', '@version 1.0')
      @git.add mkfile('Category/test2.lua', '@version 1.0')
      @git.add mkfile('Category/Sub/test3.lua', '@version 1.0')
      @git.commit 'initial commit'

      assert_output /3 new packages/ do
        assert_equal true, @indexer.run
      end

      assert_match 'Category/test2.lua', read_index
      assert_match "raw/#{@git.log(1).last.sha}/test1.lua", read_index
      assert_match 'https://github.com/cfillion/test-repository/raw', read_index

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
      @git.add mkfile('test1.lua', '@version 1.0')
      @git.commit 'initial commit'

      pwd = File.join(@git.dir.to_s, 'test')
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

      _, stderr = capture_io do
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

  def test_from_last
    setup = proc {
      @git.add mkfile('test1.lua', '@version 1.0')
      @git.commit 'initial commit'

      mkfile 'index.xml', <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" name="hello" commit="#{@git.log(1).last.sha}"/>
      XML
    }

    wrapper [], setup: setup do
      @git.add mkfile('test2.lua', '@version 1.0')
      @git.commit 'second commit'

      assert_output nil, '' do
        assert_equal true, @indexer.run
      end

      refute_match 'test1.lua', read_index
      assert_match 'test2.lua', read_index
    end
  end

  def test_from_invalid_commit
    # ensures that the indexer doesn't crash if it encounters
    # an invalid commit marker in the index file

    INVALID_HASHES.each {|hash|
      setup = proc {
        @git.add mkfile('test1.lua', '@version 1.0')
        @git.commit 'initial commit'

        mkfile 'index.xml', <<-XML
  <?xml version="1.0" encoding="utf-8"?>
  <index version="1" name="hello" commit="#{hash}"/>
        XML
      }

      wrapper [], setup: setup do
        @git.add mkfile('test2.lua', '@version 1.0')
        @git.commit 'second commit'

        assert_output nil, '' do
          assert_equal true, @indexer.run
        end

        assert_match 'test1.lua', read_index
        assert_match 'test2.lua', read_index
      end
    }
  end

  def test_amend
    setup = proc {
      @git.add mkfile('Test/test.lua', '@version 1.0')
      @git.commit 'initial commit'
      
      mkfile 'index.xml', <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" name="hello" commit="#{@git.log(1).last.sha}">
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

  def test_scan_ignore
    setup = proc { Dir.chdir @git.dir.to_s }

    wrapper ['--ignore=Hello', '--ignore=Chunky/Bacon.lua',
             '--ignore=test2.lua'], setup: setup do
      @git.add mkfile('README.md', '# Hello World')
      @git.commit 'initial commit'

      @git.add mkfile('Hello/World.lua', 'konnichiwa')
      @git.add mkfile('Chunky/Bacon.lua', 'konnichiwa')
      @git.add mkfile('Directory/test2.lua', '@version 1.0')
      @git.commit 'second commit'

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

      @git.add script
      @git.commit 'initial commit'

      @git.remove script
      @git.commit 'second commit'

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
      @git.add mkfile('test1.lua', '@version 2.0')
      @git.commit 'initial commit'

      @git.add mkfile('test2.lua', '@version 1.0')
      @git.commit 'second commit'
      options << @git.log(1).last.sha

      @git.add mkfile('test3.lua', '@version 1.1')
      @git.commit 'third commit'
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
      @git.add mkfile('test1.lua', '@version 2.0')
      @git.commit 'initial commit'

      @git.add mkfile('test2.lua', '@version 1.0')
      @git.commit 'second commit'
      options[1] = @git.log(1).last.sha

      @git.add mkfile('test3.lua', '@version 1.1')
      @git.commit 'third commit'
      options[3] = @git.log(1).last.sha
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
      @git.add mkfile('test1.lua', '@version 2.0')
      @git.commit 'initial commit'

      @git.add mkfile('test2.lua', '@version 1.0')
      @git.commit 'second commit'
      options << @git.log(1).last.sha

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
      @git.add mkfile('test1.lua', '@version 2.0')
      @git.commit 'initial commit'
      options << @git.log(1).last.sha[0..7]
    }

    wrapper options, setup: setup do
      capture_io { assert_equal true, @indexer.run }
    end
  end

  def test_invalid_hashes
    INVALID_HASHES.each {|hash|
      wrapper ['--scan', hash] do
        @git.add mkfile('README.md')
        @git.commit 'initial commit'

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
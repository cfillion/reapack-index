require File.expand_path '../../helper', __FILE__

TestCLI ||= Class.new MiniTest::Test

class TestCLI::Check < MiniTest::Test
  include CLIHelper

  def test_pass
    expected = <<-STDERR
..

Finished checks for 2 packages with 0 failures
    STDERR

    setup = proc { mkfile 'index.xml', '<index name="test"/>' }

    wrapper ['--check'], setup: setup do
      mkfile 'test1.lua', '@version 1.0'
      mkfile 'test2.lua', '@version 1.0'

      assert_output nil, expected do
        assert_equal true, @indexer.run
      end
    end
  end

  def test_failure
    expected = <<-STDERR
F.

test1.lua contains invalid metadata:
  - missing tag "version"
  - invalid value for tag "author"

Finished checks for 2 packages with 1 failure
    STDERR

    setup = proc { mkfile 'index.xml', '<index name="test"/>' }

    wrapper ['--check'], setup: setup do
      mkfile 'test1.lua', '@author'
      mkfile 'test2.lua', '@version 1.0'

      assert_output nil, expected do
        assert_equal false, @indexer.run
      end
    end
  end

  def test_quiet
    expected = <<-STDERR
test1.lua contains invalid metadata:
  - missing tag "version"
  - invalid value for tag "author"

test2.lua contains invalid metadata:
  - missing tag "version"
    STDERR

    setup = proc { mkfile 'index.xml', '<index name="test"/>' }

    wrapper ['--check', '--quiet'], setup: setup do
      mkfile 'test1.lua', '@author'
      mkfile 'test2.lua'
      mkfile 'test3.lua', '@version 1.0'

      assert_output nil, expected do
        assert_equal false, @indexer.run
      end
    end
  end

  def test_ignore
    setup = proc {
      Dir.chdir @git.dir.to_s
      mkfile 'index.xml', '<index name="test"/>'
    }

    expected = <<-STDERR
.

Finished checks for 1 package with 0 failures
    STDERR

    wrapper ['--check', '--ignore=Hello', '--ignore=Chunky/Bacon.lua',
             '--ignore=test2.lua', '--ignore=Directory/test'], setup: setup do
      mkfile 'Hello/World.lua', 'konnichiwa'
      mkfile 'Chunky/Bacon.lua', 'konnichiwa'
      mkfile 'Directory/test/1.lua', 'konnichiwa'
      mkfile 'Directory/test2.lua', '@version 1.0'

      assert_output nil, expected do
        @indexer.run
      end
    end
  end

  def test_ignore_from_config
    expected = <<-STDERR
.

Finished checks for 1 package with 0 failures
    STDERR

    setup = proc {
      mkfile '.reapack-index.conf', <<-CONFIG
--ignore=Hello
--ignore=Chunky/Bacon.lua
--ignore=test2.lua
      CONFIG

      mkfile 'index.xml', '<index name="test"/>'
    }

    wrapper ['--check'], setup: setup do
      mkfile 'Hello/World.lua', 'konnichiwa'
      mkfile 'Chunky/Bacon.lua', 'konnichiwa'
      mkfile 'Directory/test2.lua', '@version 1.0'

      assert_output nil, expected do
        @indexer.run
      end
    end
  end

  def test_unset_name_warning
    wrapper ['--check'] do
      assert_output nil, /The name of this index is unset/i do
        @indexer.run
      end
    end
  end

  def test_verbose
    expected = <<-STDERR
Path/To/test1.lua: failed
test2.lua: passed

Path/To/test1.lua contains invalid metadata:
  - missing tag "version"
  - invalid value for tag "author"

Finished checks for 2 packages with 1 failure
    STDERR

    setup = proc { mkfile 'index.xml', '<index name="test"/>' }

    _, stderr = capture_io do
      wrapper ['--check', '--verbose'], setup: setup do
        mkfile 'Path/To/test1.lua', '@author'
        mkfile 'test2.lua', '@version 1.0'

        assert_equal false, @indexer.run
      end
    end

    assert_match expected, stderr
  end
end

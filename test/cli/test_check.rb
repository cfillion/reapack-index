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
      mkfile 'cat/test1.lua', '@version 1.0'
      mkfile 'cat/test2.lua', '@version 1.0'

      assert_output nil, expected do
        assert_equal true, @cli.run
      end
    end
  end

  def test_failure
    expected = <<-STDERR
F.

1) cat/test1.lua failed:
  missing tag 'version'
  missing value for tag 'author'

Finished checks for 2 packages with 1 failure
    STDERR

    setup = proc { mkfile 'index.xml', '<index name="test"/>' }

    wrapper ['--check'], setup: setup do
      mkfile 'cat/test1.lua', '@author'
      mkfile 'cat/test2.lua', '@version 1.0'

      assert_output nil, expected do
        assert_equal false, @cli.run
      end
    end
  end

  def test_ignore_current_index
    setup = proc {
      mkfile 'background.png'
      mkfile 'index.xml', <<-XML
<index name="test">
  <category name="Hello">
    <reapack name="World.lua" type="script">
      <version name="1.0">
        <source file="../background.png"/>
      </version>
    </reapack>
  </category>
</index>
      XML
    }

    wrapper ['--check'], setup: setup do
      mkfile 'Chunky/Bacon.lua', "@version 1.0\n@provides ../background.png"

      capture_io { assert_equal true, @cli.run }
    end
  end

  def test_quiet
    expected = <<-STDERR
1) cat/test1.lua failed:
  missing tag 'version'
  missing value for tag 'author'

2) cat/test2.lua failed:
  missing tag 'version'
    STDERR

    setup = proc { mkfile 'index.xml', '<index name="test"/>' }

    wrapper ['--check', '--quiet'], setup: setup do
      mkfile 'cat/test1.lua', '@author'
      mkfile 'cat/test2.lua'
      mkfile 'cat/test3.lua', '@version 1.0'

      assert_output nil, expected do
        assert_equal false, @cli.run
      end
    end
  end

  def test_ignore
    setup = proc {
      Dir.chdir @git.path
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
        @cli.run
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
        @cli.run
      end
    end
  end

  def test_unset_name_warning
    wrapper ['--check'] do
      assert_output nil, /index is unnamed/i do
        @cli.run
      end
    end
  end

  def test_verbose
    expected = <<-STDERR
Path/To/test1.lua: failed
cat/test2.lua: passed

1) Path/To/test1.lua failed:
  missing tag 'version'
  missing value for tag 'author'

Finished checks for 2 packages with 1 failure
    STDERR

    setup = proc { mkfile 'index.xml', '<index name="test"/>' }

    _, stderr = capture_io do
      wrapper ['--check', '--verbose'], setup: setup do
        mkfile 'Path/To/test1.lua', '@author'
        mkfile 'cat/test2.lua', '@version 1.0'

        assert_equal false, @cli.run
      end
    end

    assert_match expected, stderr
  end

  def test_ignore_root
    setup = proc { mkfile 'index.xml', '<index name="test"/>' }

    _, stderr = capture_io do
      wrapper ['--check'], setup: setup do
        mkfile 'test.lua', '@version 1.0'

        assert_equal true, @cli.run
      end
    end

    assert_match 'Finished checks for 0 packages with 0 failures', stderr
  end
end

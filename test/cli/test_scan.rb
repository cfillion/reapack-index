require File.expand_path '../../helper', __FILE__

TestCLI ||= Class.new MiniTest::Test

class TestCLI::Scan < MiniTest::Test
  include CLIHelper

  def test_initial_commit
    wrapper do
      @git.create_commit 'initial commit', [
        mkfile('Category/test1.lua', '@version 1.0'),
        mkfile('Category/Sub/test2.lua', '@version 1.0'),
      ]

      assert_output /2 new packages/ do
        assert_equal true, @cli.run
      end

      assert_match 'Category/test1.lua', read_index
      assert_match 'Category/Sub/test2.lua', read_index

      assert_equal @git.last_commit.id, @cli.index.commit
      assert_equal @git.last_commit.time, @cli.index.time
    end
  end

  def test_normal_commit
    wrapper do
      @git.create_commit 'initial commit',
        [mkfile('README.md', '# Hello World')]

      @git.create_commit 'second commit', [
        mkfile('Category/test1.lua', '@version 1.0'),
        mkfile('Category/Sub/test2.lua', '@version 1.0'),
      ]

      assert_output("2 new categories, 2 new packages, 2 new versions\n") { @cli.run }

      assert_equal @git.last_commit.id, @cli.index.commit
      assert_equal @git.last_commit.time, @cli.index.time
      assert_match 'Category/test1.lua', read_index
    end
  end

  def test_workingdir_is_subdirectory
    wrapper do
      @git.create_commit 'initial commit',
        [mkfile('cat/test1.lua', '@version 1.0')]

      Dir.mkdir mkpath('test')
      Dir.chdir mkpath('test')

      assert_output(/1 new package/) { @cli.run }
      assert_match 'test1.lua', read_index
    end
  end

  def test_verbose
    stdout, stderr = capture_io do
      wrapper ['--verbose'] do
        @git.create_commit 'initial commit', [
          mkfile('cat/test.lua', '@version 1.0'),
          mkfile('cat/test.png', 'file not shown in output'),
          mkfile('test.png', 'not shown either'),
        ]

        @git.create_commit 'second commit', [
          mkfile('cat/test.lua', '@version 2.0'),
          mkfile('cat/test.jsfx', '@version 1.0'),
        ]

        File.delete mkpath('cat/test.lua')
        @git.create_commit 'third commit', [mkpath('cat/test.lua')]

        @cli.run
      end
    end

    assert_match /reading configuration from .+\.reapack-index\.conf/, stderr

    verbose = /
processing [a-f0-9]{7}: initial commit
-> indexing added file cat\/test\.lua
processing [a-f0-9]{7}: second commit
-> indexing added file cat\/test\.jsfx
-> indexing modified file cat\/test\.lua
processing [a-f0-9]{7}: third commit
-> indexing deleted file cat\/test\.lua/i

    assert_match verbose, stderr
  end

  def test_verbose_override
    wrapper ['--verbose', '--no-verbose'] do
      @git.create_commit 'initial commit', [mkfile('README.md', '# Hello World')]

      stdout, stderr = capture_io do
        @cli.run
      end

      assert_equal "empty index\n", stdout
      refute_match /processing [a-f0-9]{7}: initial commit/i, stderr
    end
  end

  def test_invalid_metadata
    wrapper do
      @git.create_commit 'initial commit',
        [mkfile('cat/test.lua', 'no version tag in this script!')]

      assert_output nil, /warning: cat\/test\.lua:\n\x20\x20missing tag/i do
        @cli.run
      end
    end
  end

  def test_no_warnings
    wrapper ['-w'] do
      @git.create_commit 'initial commit',
        [mkfile('cat/test.lua', 'no version tag in this script!')]

      _, stderr = capture_io do
        @cli.run
      end

      refute_match /warning/i, stderr
    end
  end

  def test_no_warnings_override
    wrapper ['-w', '-W'] do
      @git.create_commit 'initial commit',
        [mkfile('cat/test.lua', 'no version tag in this script!')]

      assert_output(nil, /warning/i) { @cli.run }
    end
  end

  def test_from_last
    setup = proc {
      @git.create_commit 'initial commit',
        [mkfile('cat/test1.lua', '@version 1.0')]

      mkfile 'index.xml', <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" name="hello" commit="#{@git.last_commit.id}"/>
      XML
    }

    wrapper [], setup: setup do
      @git.create_commit 'second commit',
        [mkfile('cat/test2.lua', '@version 1.0')]

      assert_output(nil, '') { @cli.run }

      refute_match 'test1.lua', read_index
      assert_match 'test2.lua', read_index
    end
  end

  def test_amend
    wrapper ['--amend'] do
      @cli.index.amend
    end
  end

  def test_no_amend
    wrapper ['--no-amend'] do
      assert_equal false, @cli.index.amend
    end
  end

  def test_scan_ignore
    setup = proc { Dir.chdir @git.path }

    wrapper ['--ignore=Hello', '--ignore=Chunky/Bacon.lua',
             '--ignore=test2.lua'], setup: setup do
      @git.create_commit 'initial commit', [
        mkfile('Hello/World.lua', '@version 1.0'),
        mkfile('Chunky/Bacon.lua', '@version 1.0'),
        mkfile('Directory/test2.lua', '@version 1.0'),
      ]

      assert_output "1 new category, 1 new package, 1 new version\n" do
        @cli.run
      end

      refute_match 'Hello/World.lua', read_index
      refute_match 'Chunky/Bacon.lua', read_index
      assert_match 'Directory/test2.lua', read_index
    end
  end

  def test_remove
    wrapper do
      @git.create_commit 'initial commit',
        [mkfile('cat/test.lua', '@version 1.0')]

      File.delete mkpath('cat/test.lua')
      @git.create_commit 'second commit', [mkpath('cat/test.lua')]

      assert_output(/1 removed package/i) { @cli.run }
      refute_match 'test.lua', read_index
    end
  end

  def test_remove_before_scan
    wrapper do
      contents = "@version 1.0\n@provides file"

      @git.create_commit 'initial commit', [
        mkfile('cat/testz.lua', contents),
        mkfile('cat/file'),
      ]

      File.delete mkpath('cat/testz.lua')
      @git.create_commit 'second commit', [
        mkpath('cat/testz.lua'),
        mkfile('cat/testa.lua', contents),
      ]

      _, stderr = capture_io do
        @cli.run
      end

      refute_match 'conflict', stderr
    end
  end

  def test_noindex_before_scan
    wrapper do
      contents = "@version 1.0\n@provides file"

      @git.create_commit 'initial commit', [
        mkfile('cat/testz.lua', contents),
        mkfile('cat/file'),
      ]

      @git.create_commit 'second commit', [
        mkfile('cat/testz.lua', contents .. "\n@noindex"),
        mkfile('cat/testa.lua', contents),
      ]

      _, stderr = capture_io do
        @cli.run
      end

      refute_match 'conflict', stderr
    end
  end

  def test_specify_commit
    # --progress is enabled to check for FloatDomainError: Infinity errors
    options = ['--progress', '--scan']

    setup = proc {
      @git.create_commit 'initial commit',
        [mkfile('cat/test1.lua', '@version 2.0')]

      @git.create_commit 'second commit',
        [mkfile('cat/test2.lua', '@version 1.0')]
      options << @git.last_commit.id

      @git.create_commit 'third commit',
        [mkfile('cat/test3.lua', '@version 1.1')]
    }

    wrapper options, setup: setup do
      capture_io { @cli.run }

      refute_match 'test1.lua', read_index, 'The initial commit was scanned'
      assert_match 'test2.lua', read_index
      refute_match 'test3.lua', read_index, 'The third commit was scanned'
    end
  end

  def test_specify_two_commits
    options = ['--scan', nil, '--scan', nil]

    setup = proc {
      @git.create_commit 'initial commit',
        [mkfile('cat/test1.lua', '@version 2.0')]

      @git.create_commit 'second commit',
        [mkfile('cat/test2.lua', '@version 1.0')]
      options[1] = @git.last_commit.id

      @git.create_commit 'third commit',
        [mkfile('cat/test3.lua', '@version 1.1')]
      options[3] = @git.last_commit.id
    }

    wrapper options, setup: setup do
      capture_io { @cli.run }

      refute_match 'test1.lua', read_index, 'The initial commit was scanned'
      assert_match 'test2.lua', read_index
      assert_match 'test3.lua', read_index
      assert_match @git.last_commit.id, read_index
    end
  end

  def test_manual_disable_commit_bump
    options = ['--scan', nil]

    setup = proc {
      @git.create_commit 'initial commit',
        [mkfile('cat/test1.lua', '@version 2.0')]
      options[1] = @git.last_commit.id
    }

    wrapper options, setup: setup do
      capture_io { @cli.run }

      assert_equal false, @cli.index.auto_bump_commit
      refute_match %Q[commit="#{options[1]}"], read_index
    end
  end

  def test_scan_file
    setup = proc {
      Dir.chdir @git.path

      @git.create_commit 'initial commit',
        [mkfile('cat/test1.lua', '@version 1')]

      @git.create_commit 'second commit', [
        mkfile('cat/test1.lua', '@version 2'),
        mkfile('cat/test2.lua', '@version 2.2'),
      ]

      @git.create_commit 'third commit',
        [mkfile('cat/test3.lua', '@version 3')]
    }

    wrapper ['--scan', 'cat/test1.lua'], setup: setup do
      capture_io { @cli.run }

      contents = read_index
      refute_match 'version name="1"', contents, 'The initial commit was scanned'
      assert_match 'version name="2"', contents
      refute_match 'test2.lua', contents, 'test2.lua was indexed'
      refute_match 'test3.lua', contents, 'The third commit was scanned'
    end
  end

  def test_scan_directory
    setup = proc {
      Dir.chdir @git.path

      mkfile('dir1/uncommited.lua')

      @git.create_commit 'initial commit',
        [mkfile('dir1/test1.lua', '@version 1')]

      @git.create_commit 'second commit', [
        mkfile('dir1/test1.lua', '@version 2'),
        mkfile('dir2/test2.lua', '@version 2.2'),
        mkfile('dir1/sub/test3.lua', '@version 3'),
      ]
    }

    wrapper ['--scan', 'dir1'], setup: setup do
      capture_io { @cli.run }

      contents = read_index
      refute_match 'version name="1"', contents, 'The initial commit was scanned'
      assert_match 'version name="2"', contents
      assert_match 'test3.lua', contents
      refute_match 'test2.lua', contents, 'test2.lua was indexed'
    end
  end

  def test_scan_directory_uncommited
    setup = proc {
      Dir.chdir @git.path

      mkfile('dir/uncommited.lua')
    }

    wrapper ['--scan', 'dir'], setup: setup do
      @git.create_commit 'initial commit', [mkfile('README.md')]

      assert_output nil, /--scan: bad file or revision: 'dir'/i do
        assert_throws(:stop, false) { @cli.run }
      end
    end
  end

  def test_scan_directory_absolute
    options = ['--scan', nil]

    setup = proc {
      @git.create_commit 'initial commit',
        [mkfile('dir/test.lua', '@version 1')]
      options[1] = mkpath('dir')
    }

    wrapper options, setup: setup do
      capture_io { @cli.run }

      assert 'test.lua', read_index
    end
  end

  def test_reset
    options = ['--scan']

    setup = proc {
      @git.create_commit 'initial commit',
        [mkfile('cat/test1.lua', '@version 2.0')]

      @git.create_commit 'second commit',
        [mkfile('cat/test2.lua', '@version 1.0')]
      options << @git.last_commit.id

      options << '--scan'
    }

    wrapper options, setup: setup do
      capture_io { @cli.run }
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
      capture_io { @cli.run }
    end
  end

  def test_invalid_hashes
    INVALID_HASHES.each {|hash|
      wrapper ['--scan', hash] do
        @git.create_commit 'initial commit', [mkfile('README.md')]

        assert_output nil, /--scan: bad file or revision: '#{Regexp.escape hash}'/i do
          assert_throws(:stop, false) { @cli.run }
        end
      end
    }
  end

  def test_report_right_invalid_hash
    setup = proc { Dir.chdir @git.path }

    wrapper ['--scan', 'README.md', '--scan', INVALID_HASHES.first], setup: setup do
      @git.create_commit 'initial commit', [mkfile('README.md')]

      _, stderr = capture_io do
        assert_throws(:stop, false) { @cli.run }
      end
      
      refute_match 'README.md', stderr
      assert_match INVALID_HASHES.first, stderr
    end
  end

  def test_rebuild
    setup = proc {
      @git.create_commit 'initial commit',
        [mkfile('cat/test1.lua', '@version 1.0')]

      mkfile 'index.xml', <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" name="hello" commit="#{@git.last_commit.id}">
  <category name="Other">
    <reapack name="Hello.lua" type="script" />
  </category>
</index>
      XML
    }

    wrapper ['--rebuild'], setup: setup do
      @git.create_commit 'second commit',
        [mkfile('cat/test2.lua', '@version 1.0')]

      assert_output(nil, '') { @cli.run }

      contents = read_index
      assert_match 'test1.lua', contents
      refute_match 'Hello.lua', contents
    end
  end

  def test_rebuild_override
    setup = proc {
      @git.create_commit 'initial commit',
        [mkfile('cat/test1.lua', '@version 1.0')]

      mkfile 'index.xml', <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" name="hello" commit="#{@git.last_commit.id}">
  <category name="Other">
    <reapack name="Hello.lua" type="script" />
  </category>
</index>
      XML
    }

    wrapper ['--rebuild', '--scan'], setup: setup do
      @git.create_commit 'second commit',
        [mkfile('cat/test2.lua', '@version 1.0')]

      assert_output(nil, '') { @cli.run }

      contents = read_index
      refute_match 'test1.lua', contents
      assert_match 'Hello.lua', contents
    end
  end

  def test_no_scan
    options = ['--no-scan']

    setup = proc {
      @git.create_commit 'initial commit',
        [mkfile('cat/test1.lua', '@version 1.0')]
    }

    wrapper options, setup: setup do
      capture_io { @cli.run }

      refute_match 'test1.lua', read_index, 'The initial commit was scanned'
    end
  end

  def test_no_arguments
    wrapper ['--scan'] do; end
  end

  def test_strict_mode
    wrapper do
      refute @cli.index.strict
    end

    wrapper ['--no-strict'] do
      refute @cli.index.strict
    end

    wrapper ['--strict'] do
      assert @cli.index.strict
    end
  end
end

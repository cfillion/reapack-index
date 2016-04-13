require File.expand_path '../helper', __FILE__

class TestGit < MiniTest::Test
  include GitHelper

  def setup
    @path, @repo = init_git
  end

  def teardown
    FileUtils.rm_r @path
  end

  def test_path
    realpath = Pathname.new(@path).realpath
    assert_equal realpath.to_s, @git.path
  end

  def test_create_initial_commit
    index = @repo.index
    index.add @git.relative_path(mkfile('ignored_staged'))
    index.write

    mkfile 'ignored'

    assert_equal true, @git.empty?
    @git.create_commit 'initial commit', [mkfile('file')]
    assert_equal false, @git.empty?

    commit = @git.last_commit
    assert_equal 'initial commit', commit.message
    assert_equal ['file'], commit.each_diff.map {|d| d.file }
    assert_equal ['file'], commit.filelist
  end

  def test_create_subsequent_commit
    @git.create_commit 'initial commit', [mkfile('file1')]

    mkfile 'ignored'

    index = @repo.index
    index.add @git.relative_path(mkfile('ignored_staged'))
    index.write

    @git.create_commit 'second commit', [mkfile('file2')]

    commit = @git.last_commit
    assert_equal 'second commit', commit.message
    assert_equal ['file2'], commit.each_diff.map {|d| d.file }
    assert_equal ['file1', 'file2'], commit.filelist
  end

  def test_multibyte_filename
    name = "\342\200\224.lua"
    file = mkfile name

    @git.create_commit 'initial commit', [file]
    assert_equal name, @git.last_commit.each_diff.first.file
  end

  def test_invalid_char_sequence
    content = "\x97"
    @git.create_commit 'initial commit', [mkfile('test.lua', content)]

    assert_equal content, @git.last_commit.each_diff.first.new_content
  end
end

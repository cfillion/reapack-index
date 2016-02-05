require File.expand_path '../helper', __FILE__

class TestIndex < MiniTest::Test
  def setup
    @real_path = File.expand_path '../indexes/index.xml', __FILE__
    @dummy_path = File.expand_path '../indexes/new_index.xml', __FILE__
    @scripts_path = File.expand_path '../scripts/', __FILE__

    @commit = '399f5609cff3e6fd92b5542d444fbf86da0443c6'
  end

  def teardown
    File.delete @dummy_path if File.exists? @dummy_path
  end

  def test_version_and_commit
    index = ReaPack::Index.new @real_path

    assert_equal 1, index.version
    assert_equal @commit, index.commit
  end

  def test_save
    index = ReaPack::Index.new @real_path

    index.write @dummy_path
    assert_equal File.read(index.path), File.read(@dummy_path)
  end

  def test_mkdir
   path = File.expand_path '../dummy_dir/test.xml', __FILE__
   dirname = File.dirname path

   refute File.exist? dirname

   index = ReaPack::Index.new path
   index.write!

   assert File.exist? dirname
   FileUtils.rm_r dirname
  end

  def test_new
    index = ReaPack::Index.new \
      File.expand_path '../indexes/does_not_exists.xml', __FILE__

    assert index.modified?
    assert_equal "empty index", index.changelog

    assert_equal 1, index.version
    assert_nil index.commit
  end

  def test_type_of
    assert_nil ReaPack::Index.type_of('src/main.cpp')

    assert_equal :script, ReaPack::Index.type_of('Track/instrument_track.lua')
    assert_equal :script, ReaPack::Index.type_of('Track/instrument_track.eel')
  end

  def test_source_for
    assert_nil ReaPack::Index.source_for('http://google.com')

    assert_equal 'https://github.com/User/Repo/raw/$commit/$path',
      ReaPack::Index.source_for('git@github.com:User/Repo.git')

    assert_equal 'https://github.com/User/Repo/raw/$commit/$path',
      ReaPack::Index.source_for('https://github.com/User/Repo.git')
  end

  def test_scan_unknown_type
    index = ReaPack::Index.new @dummy_path
    index.commit = @commit

    index.scan 'src/main.cpp', String.new
    index.write!

    path = File.expand_path '../indexes/empty.xml', __FILE__
    assert_equal File.read(path), File.read(@dummy_path)
  end

  def test_scan_new_script
    index = ReaPack::Index.new @dummy_path

    index.pwd = @scripts_path
    index.source_pattern = 'http://google.com/$path'
    index.scan 'Track/Instrument Track.lua', <<-IN
      @version 1.0
      @changelog
        Line 1
        Line 2
    IN

    assert index.modified?
    assert_equal '1 new category, 1 new package, 1 new version', index.changelog

    index.write!

    refute index.modified?
    assert_nil index.changelog

    path = File.expand_path '../indexes/Instrument Track.lua.xml', __FILE__
    assert_equal File.read(path), File.read(index.path)
  end

  def test_change_changelog
    index = ReaPack::Index.new \
      File.expand_path '../indexes/Instrument Track.lua.xml', __FILE__

    index.pwd = @scripts_path
    index.source_pattern = 'http://google.com/$path'
    index.scan 'Track/Instrument Track.lua', <<-IN
      @version 1.0
      @changelog New Changelog!
    IN

    refute index.modified?
  end

  def test_change_changelog_amend
    index = ReaPack::Index.new \
      File.expand_path '../indexes/Instrument Track.lua.xml', __FILE__

    index.amend = true
    index.pwd = @scripts_path
    index.source_pattern = 'http://google.com/$path'
    index.scan 'Track/Instrument Track.lua', <<-IN
      @version 1.0
      @changelog New Changelog!
    IN

    assert index.modified?
  end

  def test_remove_changelog_amend
    index = ReaPack::Index.new \
      File.expand_path '../indexes/Instrument Track.lua.xml', __FILE__

    index.amend = true
    index.pwd = @scripts_path
    index.source_pattern = 'http://google.com/$path'
    index.scan 'Track/Instrument Track.lua', <<-IN
      @version 1.0
    IN

    assert index.modified?

    index.write @dummy_path
    assert index.modified? # still modified after write() since write!() is not called

    path = File.expand_path '../indexes/no_changelog.xml', __FILE__
    assert_equal File.read(path), File.read(@dummy_path)
  end

  def test_amend_identical_with_changelog
    path = File.expand_path '../indexes/Instrument Track.lua.xml', __FILE__
    index = ReaPack::Index.new path

    index.amend = true
    index.pwd = @scripts_path
    index.source_pattern = 'http://google.com/$path'
    index.scan 'Track/Instrument Track.lua', <<-IN
      @version 1.0
      @changelog
        Line 1
        Line 2
    IN

    refute index.modified?

    index.write @dummy_path
    assert_equal File.read(path), File.read(@dummy_path)
  end

  def test_amend_identical_no_changelog
    index = ReaPack::Index.new @dummy_path

    index.amend = true
    index.pwd = @scripts_path
    index.source_pattern = 'http://google.com/$path'
    index.scan 'Track/Instrument Track.lua', <<-IN
      @version 1.0
    IN

    index.write!

    index.scan 'Track/Instrument Track.lua', <<-IN
      @version 1.0
    IN

    refute index.modified?
  end

  def test_scan_change_source_pattern
    path = File.expand_path '../indexes/Instrument Track.lua.xml', __FILE__
    index = ReaPack::Index.new path

    index.pwd = @scripts_path
    index.source_pattern = 'https://duckduckgo.com/$path'
    index.scan 'Track/Instrument Track.lua', <<-IN
      @version 1.0
      @changelog
        Line 1
        Line 2
    IN

    refute index.modified?
  end

  def test_scan_source_with_commit
    path = File.expand_path @dummy_path, __FILE__
    index = ReaPack::Index.new path

    index.pwd = @scripts_path
    index.source_pattern = 'https://google.com/$commit/$path'
    index.commit = 'commit-sha1'

    index.scan 'Category Name/Hello World.lua', <<-IN
      @version 1.0
    IN

    index.write!

    path = File.expand_path '../indexes/source_commit.xml', __FILE__
    assert_equal File.read(path), File.read(@dummy_path)
  end

  def test_validate_standalone
    refute_nil ReaPack::Index.validate_file @real_path
  end

  def test_validate_noindex
    assert_nil ReaPack::Index.validate_file \
      File.expand_path '../scripts/noindex.lua', __FILE__
  end

  def test_validate_during_scan
    index = ReaPack::Index.new @dummy_path
    index.commit = @commit

    error = assert_raises ReaPack::Index::Error do
      index.scan 'Cat/test.lua', 'hello'
    end

    index.write!

    assert_match /\AInvalid metadata in Cat\/test\.lua:/, error.message

    path = File.expand_path '../indexes/empty.xml', __FILE__
    assert_equal File.read(path), File.read(@dummy_path)
  end

  def test_no_default_source_pattern
    index = ReaPack::Index.new @dummy_path

    error = assert_raises ReaPack::Index::Error do
      index.scan 'Track/Instrument Track.lua', <<-IN
        @version 1.0
      IN
    end

    assert_match /\ASource pattern is unset/, error.message
  end

  def test_remove
    index = ReaPack::Index.new @real_path

    index.remove 'Category Name/Hello World.lua'

    assert index.modified?
    assert_equal '1 removed package', index.changelog

    index.write @dummy_path

    path = File.expand_path '../indexes/empty.xml', __FILE__
    assert_equal File.read(path), File.read(@dummy_path)
  end

  def test_remove_not_found
    index = ReaPack::Index.new @real_path

    index.remove 'Cat/test.lua'
    refute index.modified?
  end

  def test_scan_no_category
    index = ReaPack::Index.new @dummy_path

    index.pwd = @scripts_path
    index.source_pattern = 'http://google.com/$path'
    index.scan 'test.lua', <<-IN
      @version 1.0
    IN

    index.write!

    path = File.expand_path '../indexes/default_category.xml', __FILE__
    assert_equal File.read(path), File.read(index.path)
  end

  def test_scan_noindex
    index = ReaPack::Index.new \
      File.expand_path '../indexes/Instrument Track.lua.xml', __FILE__

    index.pwd = @scripts_path
    index.source_pattern = 'http://google.com/$path'
    index.scan 'Track/Instrument Track.lua', <<-IN
      @noindex
    IN

    assert index.modified?

    index.commit = @commit
    index.write @dummy_path

    path = File.expand_path '../indexes/empty.xml', __FILE__
    assert_equal File.read(path), File.read(@dummy_path)
  end

  def test_scan_dependencies
    index = ReaPack::Index.new @dummy_path

    index.pwd = @scripts_path
    index.source_pattern = 'http://google.com/$path'
    index.scan 'Track/Instrument Track.lua', <<-IN
      @version 1.0
      @provides
        Resources/unicode.dat
        test.png
    IN

    assert index.modified?

    index.write!

    path = File.expand_path '../indexes/dependencies.xml', __FILE__
    assert_equal File.read(path), File.read(@dummy_path)
  end

  def test_scan_dependencies_from_root
    index = ReaPack::Index.new @dummy_path

    index.pwd = @scripts_path
    index.source_pattern = 'http://google.com/$path'
    index.scan 'test.lua', <<-IN
      @version 1.0
      @provides
        Track/test.png
    IN

    assert index.modified?

    index.write!

    path = File.expand_path '../indexes/dependencies_from_root.xml', __FILE__
    assert_equal File.read(path), File.read(@dummy_path)
  end

  def test_missing_dependency
    index = ReaPack::Index.new @dummy_path

    index.pwd = @scripts_path
    index.commit = @commit
    index.source_pattern = 'http://google.com/$path'
    error = assert_raises ReaPack::Index::Error do
      index.scan 'Track/Instrument Track.lua', <<-IN
        @version 1.0
        @provides
          404.html
      IN
    end

    assert_equal 'Track/404.html: No such file or directory', error.message

    index.write!

    path = File.expand_path '../indexes/empty.xml', __FILE__
    assert_equal File.read(path), File.read(@dummy_path)
  end

  def test_duplicate_dependencies
    index = ReaPack::Index.new @dummy_path

    index.pwd = @scripts_path
    index.commit = @commit
    index.source_pattern = 'http://google.com/$path'
    error = assert_raises ReaPack::Index::Error do
      index.scan 'Track/Instrument Track.lua', <<-IN
        @version 1.0
        @provides
          test.png
          test.png
      IN
    end

    assert_equal "Invalid metadata in Track/Instrument Track.lua:" +
      "\n  invalid value for tag \"provides\": duplicate file (test.png)",
      error.message
  end

  def test_do_not_bump_sources
    index = ReaPack::Index.new File.expand_path '../indexes/source_commit.xml', __FILE__

    index.pwd = @scripts_path
    index.source_pattern = 'https://google.com/$commit/$path'
    index.commit = 'new-commit-hash'

    index.scan 'Category Name/Hello World.lua', <<-IN
      @version 1.0
    IN

    refute index.modified?
    index.write @dummy_path

    path = File.expand_path '../indexes/replaced_commit.xml', __FILE__
    assert_equal File.read(path), File.read(@dummy_path)
  end

  def test_bump_sources_amend
    index = ReaPack::Index.new File.expand_path '../indexes/source_commit.xml', __FILE__

    index.amend = true

    index.pwd = @scripts_path
    index.source_pattern = 'https://google.com/$commit/$path'
    index.commit = 'new-commit-hash'

    index.scan 'Category Name/Hello World.lua', <<-IN
      @version 1.0
    IN

    assert_equal '1 updated package, 1 updated version', index.changelog
    assert index.modified?
    index.write @dummy_path

    path = File.expand_path '../indexes/bumped_sources.xml', __FILE__
    assert_equal File.read(path), File.read(@dummy_path)
  end

  def test_scan_wordpress
    index = ReaPack::Index.new @dummy_path

    index.pwd = @scripts_path
    index.source_pattern = 'http://google.com/$path'
    index.scan 'Track/Instrument Track.lua', <<-IN
/**
 * Version: 1.1
 */

/**
 * Changelog:
 * v1.2 (2010-01-01)
	+ Line 1
	+ Line 2
 * v1.1 (2011-01-01)
	+ Line 3
	+ Line 4
 * v1.0 (2012-01-01)
	+ Line 5
	+ Line 6
 */

 Test
    IN

    index.write!

    path = File.expand_path '../indexes/wordpress.xml', __FILE__
    assert_equal File.read(path), File.read(index.path)
  end

  def test_author
    index = ReaPack::Index.new @dummy_path

    index.pwd = @scripts_path
    index.source_pattern = 'http://google.com/$path'
    index.scan 'Track/Instrument Track.lua', <<-IN
      @version 1.0
      @author cfillion
    IN

    assert index.modified?

    index.write @dummy_path

    path = File.expand_path '../indexes/version_author.xml', __FILE__
    assert_equal File.read(path), File.read(@dummy_path)
  end

  def test_author_boolean
    index = ReaPack::Index.new @dummy_path

    index.pwd = @scripts_path
    index.source_pattern = 'http://google.com/$path'

    error = assert_raises ReaPack::Index::Error do
     index.scan 'Track/Instrument Track.lua', <<-IN
       @version 1.0
       @author
     IN
    end

    assert_match /Invalid metadata/, error.message
  end

  def test_author_multiline
    index = ReaPack::Index.new @dummy_path

    index.pwd = @scripts_path
    index.source_pattern = 'http://google.com/$path'

    error = assert_raises ReaPack::Index::Error do
     index.scan 'Track/Instrument Track.lua', <<-IN
       @version 1.0
       @author
         hello
         world
     IN
    end

    assert_match /Invalid metadata/, error.message
  end
end

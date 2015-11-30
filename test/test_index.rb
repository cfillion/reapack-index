require File.expand_path '../helper', __FILE__

class TestIndex < MiniTest::Test
  def setup
    @dummy_path = File.expand_path '../db/new_database.xml', __FILE__
  end

  def teardown
    File.delete @dummy_path if File.exists? @dummy_path
  end

  def test_version_and_commit
    db = ReaPack::Index.new \
      File.expand_path '../db/database.xml', __FILE__

    assert_equal 1, db.version
    assert_equal '399f5609cff3e6fd92b5542d444fbf86da0443c6', db.commit
  end

  def test_save
    db = ReaPack::Index.new \
      File.expand_path '../db/database.xml', __FILE__

    path = File.expand_path '../db/database.xml.new', __FILE__
    db.write path
    assert_equal File.read(db.path), File.read(path)
  ensure
    File.delete path
  end

  def test_new
    db = ReaPack::Index.new \
      File.expand_path '../db/does_not_exists.xml', __FILE__

    assert_equal 1, db.version
    assert_nil db.commit
  end

  def test_type_of
    assert_nil ReaPack::Index.type_of('src/main.cpp')

    assert_equal :script, ReaPack::Index.type_of('Track/instrument_track.lua')
    assert_equal :script, ReaPack::Index.type_of('Track/instrument_track.eel')
  end

  def test_source_for
    assert_nil ReaPack::Index.source_for('http://google.com')

    assert_equal 'https://github.com/User/Repo/raw/master/$path',
      ReaPack::Index.source_for('git@github.com:User/Repo.git')

    assert_equal 'https://github.com/User/Repo/raw/master/$path',
      ReaPack::Index.source_for('https://github.com/User/Repo.git')
  end

  def test_scan_unknown_type
    db = ReaPack::Index.new @dummy_path

    db.scan 'src/main.cpp', String.new
    refute db.modified?
    assert_nil db.changelog
  end

  def test_scan_new_script
    db = ReaPack::Index.new @dummy_path
    assert_nil db.changelog

    db.source_pattern = 'http://google.com/$path'
    db.scan 'Track/Instrument Track.lua', <<-IN
      @author cfillion
      @version 1.0
      @changelog
        Line 1
        Line 2
    IN

    assert db.modified?
    assert_equal '1 new category, 1 new package, 1 new version, ' \
      '1 script', db.changelog

    db.write!

    refute db.modified?
    assert_nil db.changelog

    path = File.expand_path '../db/Instrument Track.lua.xml', __FILE__
    assert_equal File.read(path), File.read(db.path)
  end

  def test_remove_changelog
    db = ReaPack::Index.new \
      File.expand_path '../db/Instrument Track.lua.xml', __FILE__

    db.source_pattern = 'http://google.com/$path'
    db.scan 'Track/Instrument Track.lua', <<-IN
      @author cfillion
      @version 1.0
    IN

    assert db.modified?

    db.write @dummy_path
    assert db.modified? # still modified after write() since write!() is not called

    path = File.expand_path '../db/no_changelog.xml', __FILE__
    assert_equal File.read(path), File.read(@dummy_path)
  end

  def test_scan_identical
    path = File.expand_path '../db/Instrument Track.lua.xml', __FILE__
    db = ReaPack::Index.new path

    db.source_pattern = 'http://google.com/$path'
    db.scan 'Track/Instrument Track.lua', <<-IN
      @author cfillion
      @version 1.0
      @changelog
        Line 1
        Line 2
    IN

    refute db.modified?

    db.write @dummy_path
    assert_equal File.read(path), File.read(@dummy_path)
  end

  def test_scan_change_source_pattern
    path = File.expand_path '../db/Instrument Track.lua.xml', __FILE__
    db = ReaPack::Index.new path

    db.source_pattern = 'http://duckduckgo.com/$path'
    db.scan 'Track/Instrument Track.lua', <<-IN
      @author cfillion
      @version 1.0
      @changelog
        Line 1
        Line 2
    IN

    assert db.modified?
  end

  def test_validate_standalone
    refute_empty ReaPack::Index.validate_file \
      File.expand_path '../db/database.xml', __FILE__
  end

  def test_validate_during_scan
    db = ReaPack::Index.new @dummy_path

    error = assert_raises do
      db.scan 'Cat/test.lua', 'hello'
    end

    assert_match /\AInvalid metadata in Cat\/test\.lua:/, error.message
  end

  def test_no_default_source_pattern
    db = ReaPack::Index.new @dummy_path

    error = assert_raises do
      db.scan 'Track/Instrument Track.lua', <<-IN
        @author cfillion
        @version 1.0
      IN
    end

    assert_match /\ASource pattern is unset/, error.message
  end
end

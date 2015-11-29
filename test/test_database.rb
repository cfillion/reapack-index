require File.expand_path '../helper', __FILE__

class TestDatabase < MiniTest::Test

  def test_version_and_commit
    db = ReaPack::Indexer::Database.new \
      File.expand_path '../db/database.xml', __FILE__

    assert_equal 1, db.version
    assert_equal '399f5609cff3e6fd92b5542d444fbf86da0443c6', db.commit
  end

  def test_save
    db = ReaPack::Indexer::Database.new \
      File.expand_path '../db/database.xml', __FILE__

    path = File.expand_path '../db/database.xml.new', __FILE__
    db.write path
    assert_equal File.read(db.path), File.read(path)
  ensure
    File.delete path
  end

  def test_new
    db = ReaPack::Indexer::Database.new \
      File.expand_path '../db/does_not_exists.xml', __FILE__

    assert_equal 1, db.version
    assert_nil db.commit
  end
end

require File.expand_path '../../helper', __FILE__

TestIndex ||= Class.new MiniTest::Test

class TestIndex::Metadata < MiniTest::Test
  include IndexHelper

  def test_add_anonymous_link
    index = ReaPack::Index.new @dummy_path

    assert_equal 0, index.links(:website).size
    index.eval_link :website, 'http://test.com'
    assert_equal 1, index.links(:website).size

    assert_equal '1 new website link, empty index', index.changelog

    index.write!
  end

  def test_add_named_link
    index = ReaPack::Index.new @dummy_path

    assert_equal 0, index.links(:website).size
    index.eval_link :website, 'Test=http://test.com/hello=world'
    assert_equal 1, index.links(:website).size

    assert_equal '1 new website link, empty index', index.changelog

    index.write!
    expected = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1">
  <metadata>
    <link rel="website" href="http://test.com/hello=world">Test</link>
  </metadata>
</index>
    XML

    index.write!
    assert_equal expected, File.read(index.path)
  end

  def test_edit_link
    index = ReaPack::Index.new @dummy_path

    index.eval_link :website, 'Test=http://test.com'
    index.eval_link :website, 'Test=http://test.com'
    assert_equal '1 new website link, empty index', index.changelog

    index.eval_link :website, 'Test=http://test.com/hello'
    assert_equal '1 new website link, 1 modified website link, empty index',
      index.changelog
  end

  def test_remove_link_by_name
    index = ReaPack::Index.new @dummy_path
    index.eval_link :website, 'Test=http://test.com'
    index.eval_link :website, '-Test'

    assert_equal '1 new website link, 1 removed website link, empty index', index.changelog
  end

  def test_remove_link_by_url
    index = ReaPack::Index.new @dummy_path

    index.eval_link :website, 'Test=http://test.com'
    index.eval_link :website, '-http://test.com'

    assert_equal '1 new website link, 1 removed website link, empty index', index.changelog
  end

  def test_description
    index = ReaPack::Index.new @dummy_path
    index.write!

    assert_empty index.description
    assert_equal false, index.modified?

    index.description = 'Hello World'
    refute_empty index.description
    assert_equal true, index.modified?
    assert_equal '1 modified metadata', index.changelog

    index.write!

    index.description = 'Hello World'
    assert_equal false, index.modified?
  end

  def test_name
    index = ReaPack::Index.new @dummy_path
    assert_empty index.name

    index.name = 'Hello World'
    assert_equal '1 modified metadata, empty index', index.changelog

    error = assert_raises ReaPack::Index::Error do index.name = '.'; end
    assert_raises ReaPack::Index::Error do index.name = 'hello/world'; end
    assert_equal "Invalid name: '.'", error.message

    assert_equal 'Hello World', index.name

    expected = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" name="Hello World"/>
    XML

    index.write!
    assert_equal expected, File.read(index.path)
  end
end

require File.expand_path '../helper', __FILE__

class TestVersion < MiniTest::Test
  def test_create
    before = make_node '<reapack />'
    after = <<-XML
<reapack>
  <version name="1.0"/>
</reapack>
    XML

    ver = ReaPack::Index::Version.new '1.0', before
    assert ver.is_new?, 'version is not new'
    assert ver.modified?, 'version is not modified'

    assert_equal after.chomp, before.to_s
  end

  def test_use
    before = make_node '<version name="1.0"/>'

    ver = ReaPack::Index::Version.new before
    refute ver.is_new?, 'version is new'
    refute ver.modified?, 'version is modified'
  end

  def test_change_author
    before = make_node '<version name="1.0"/>'
    after = '<version name="1.0" author="cfillion"/>'

    ver = ReaPack::Index::Version.new before
    assert_empty ver.author

    ver.author = 'cfillion'
    assert ver.modified?, 'version is not modified'
    assert_equal 'cfillion', ver.author

    assert_equal after, before.to_s
  end

  def test_set_same_author
    before = make_node '<version name="1.0" author="cfillion"/>'

    ver = ReaPack::Index::Version.new before

    assert_equal 'cfillion', ver.author
    ver.author = ver.author

    refute ver.modified?, 'version is modified'
  end

  def test_remove_author
    before = make_node '<version name="1.0" author="cfillion"/>'
    after = '<version name="1.0"/>'

    ver = ReaPack::Index::Version.new before
    assert_equal 'cfillion', ver.author

    ver.author = nil
    assert ver.modified?, 'version is not modified'

    assert_equal after, before.to_s
  end

  def test_set_nil_author
    before = make_node '<version name="1.0"/>'
    after = '<version name="1.0"/>'

    ver = ReaPack::Index::Version.new before
    assert_empty ver.author

    ver.author = nil
    refute ver.modified?, 'version is modified'

    assert_equal after, before.to_s
  end

  def test_add_source
    before = make_node '<version name="1.0"/>'
    after = <<-XML
<version name="1.0">
  <source platform="all" file="test.lua">http://files.cfillion.tk/test.lua</source>
</version>
XML

    ver = ReaPack::Index::Version.new before
    ver.add_source :all, 'test.lua', 'http://files.cfillion.tk/test.lua'

    assert ver.modified?, 'version is not modified'

    assert_equal after.chomp, before.to_s
  end

  def test_escape_source_url
    before = make_node '<version name="1.0"/>'
    after = <<-XML
<version name="1.0">
  <source platform="all" file="test.lua">http://files.cfillion.tk/hello%20world.lua</source>
</version>
XML

    ver = ReaPack::Index::Version.new before
    ver.add_source :all, 'test.lua', 'http://files.cfillion.tk/hello world.lua'

    assert_equal after.chomp, before.to_s
  end

  def test_replace_sources
    before = make_node <<-XML
<version name="1.0">
  <source platform="all" file="old.lua">http://files.cfillion.tk/old.lua</source>
</version>
    XML

    after = <<-XML
<version name="1.0">
  <source platform="all" file="new.lua">http://files.cfillion.tk/new.lua</source>
</version>
XML

    ver = ReaPack::Index::Version.new before

    ver.replace_sources do
      ver.add_source :all, 'new.lua', 'http://files.cfillion.tk/new.lua'
    end

    assert ver.modified?, 'version is not modified'

    assert_equal after.chomp, before.to_s
  end

  def test_replace_sources_to_identical
    before = make_node <<-XML
<version name="1.0">
  <source platform="all" file="test.lua">http://files.cfillion.tk/test.lua</source>
</version>
    XML

    ver = ReaPack::Index::Version.new before

    ver.replace_sources do
      ver.add_source :all, 'test.lua', 'http://files.cfillion.tk/test.lua'
    end

    refute ver.modified?, 'version is modified'
  end

  def test_set_changelog
    before = make_node '<version name="1.0"/>'

    ver = ReaPack::Index::Version.new before
    ver.changelog = 'Refactored the test suite'

    assert ver.modified?, 'version is not modified'
  end
end
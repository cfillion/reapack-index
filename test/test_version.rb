require File.expand_path '../helper', __FILE__

class TestVersion < MiniTest::Test
  include XMLHelper

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

  def test_set_author
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

  def test_set_time
    before = make_node '<version name="1.0"/>'
    after = '<version name="1.0" time="2016-02-12T01:16:40Z"/>'

    time = Time.new 2016, 2, 11, 20, 16, 40, -5 * 3600

    ver = ReaPack::Index::Version.new before
    assert_nil ver.time

    ver.time = time
    assert ver.modified?, 'version is not modified'
    assert_equal time, ver.time

    assert_equal after, before.to_s
  end

  def test_set_same_time
    ver = ReaPack::Index::Version.new \
      make_node '<version name="1.0" time="2016-02-12T01:16:40Z"/>'

    time = Time.new 2016, 2, 11, 20, 16, 40, -5 * 3600

    assert_equal time, ver.time
    ver.time = time

    refute ver.modified?, 'version is modified'
  end

  def test_remove_time
    before = make_node '<version name="1.0" time="2016-02-12T01:16:40Z"/>'
    after = '<version name="1.0"/>'

    ver = ReaPack::Index::Version.new before

    ver.time = nil
    assert ver.modified?, 'version is not modified'

    assert_equal after, before.to_s
  end

  def test_add_source
    before = make_node '<version name="1.0"/>'
    after = <<-XML
<version name="1.0">
  <source platform="all" file="test.lua">http://files.cfillion.tk/test.lua</source>
</version>
    XML

    src = ReaPack::Index::Source.new nil, 'test.lua',
      'http://files.cfillion.tk/test.lua'

    ver = ReaPack::Index::Version.new before
    ver.add_source src

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

    src = ReaPack::Index::Source.new \
      :all, 'test.lua', 'http://files.cfillion.tk/hello world.lua'
    assert_equal 'http://files.cfillion.tk/hello world.lua', src.url

    src.make_node before

    assert_equal after.chomp, before.to_s
  end

  def test_invalid_source_url
    after = '<version name="1.0"/>'
    before = make_node after

    src = ReaPack::Index::Source.new :all, 'test.lua', 'http://hello world/'
    assert_equal 'http://hello world/', src.url

    error = assert_raises ReaPack::Index::Error do
      src.make_node before
    end

    refute_empty error.message
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

  def test_source_platform
    src = ReaPack::Index::Source.new
    assert_equal :all, src.platform

    src.platform = :windows
    assert_equal :windows, src.platform

    error = assert_raises ReaPack::Index::Error do
      src.platform = :hello
    end

    assert_equal "invalid platform 'hello'", error.message

    src.platform = nil
    assert_equal :all, src.platform
  end

  def test_version_without_sources
    ver = ReaPack::Index::Version.new make_node('<version name="1.0"/>')

    error = assert_raises ReaPack::Index::Error do
      ver.replace_sources do; end
    end

    assert_equal 'no files provided', error.message
  end
end

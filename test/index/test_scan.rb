require File.expand_path '../../helper', __FILE__

TestIndex ||= Class.new MiniTest::Test

class TestIndex::Scan < MiniTest::Test
  include IndexHelper

  def test_ignore_unknown_type
    index = ReaPack::Index.new @dummy_path

    index.scan 'src/main.cpp', String.new
    index.write!

    expected = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1"/>
    XML

    assert_equal expected, File.read(index.path)
  end

  def test_new_package
    index = ReaPack::Index.new @dummy_path
    index.files = ['Category/Path/Instrument Track.lua']
    index.url_template = 'http://host/$path'

    index.scan index.files.first, <<-IN
      @version 1.0
      @changelog Hello World
    IN

    assert_equal true, index.modified?
    assert_equal '1 new category, 1 new package, 1 new version', index.changelog

    index.write!

    assert_equal false, index.modified?
    assert_empty index.changelog

    expected = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1">
  <category name="Category/Path">
    <reapack name="Instrument Track.lua" type="script">
      <version name="1.0">
        <changelog><![CDATA[Hello World]]></changelog>
        <source main="main">http://host/Category/Path/Instrument%20Track.lua</source>
      </version>
    </reapack>
  </category>
</index>
    XML

    assert_equal expected, File.read(index.path)
  end

  def test_package_in_root
    index = ReaPack::Index.new @dummy_path
    index.files = ['script.lua', 'Hello/World']
    index.url_template = 'http://host/$path'

    index.scan index.files.first, <<-IN
      @version 1.0
      @provides Hello/World
    IN

    index.write!
    refute_match '<reapack', File.read(index.path)
  end

  def test_noindex
    index = ReaPack::Index.new @real_path

    index.scan 'script.lua', '@noindex'

    assert_equal false, index.modified?
  end

  def test_noindex_autoremove
    index = ReaPack::Index.new @real_path
    index.commit = @commit

    index.scan 'Category Name/Hello World.lua', '@noindex'

    assert_equal true, index.modified?
    assert_equal '1 removed package', index.changelog

    index.write @dummy_path
    contents = File.read @dummy_path

    assert_match @commit, contents
    refute_match '<category', contents
  end

  def test_auto_bump_commit_enabled
    index = ReaPack::Index.new @real_path
    index.commit = @commit

    assert_equal true, index.auto_bump_commit
    refute_equal @commit, index.last_commit

    index.scan 'Category Name/Hello World.lua', '@version 1.0'
    assert_equal @commit, index.last_commit
  end

  def test_auto_bump_commit_disabled
    index = ReaPack::Index.new @real_path
    index.commit = @commit
    index.auto_bump_commit = false

    index.scan 'Category Name/Hello World.lua', '@version 1.0'
    refute_equal @commit, index.last_commit
  end

  def test_strict_mode
    index = ReaPack::Index.new @dummy_path
    index.strict = true
    index.url_template = 'http://host/$path'
    index.files = ['Category/script.lua']

    error = assert_raises ReaPack::Index::Error do
      index.scan index.files.first, "@version 1.0\n@qwerty"
    end

    assert_equal "unknown tag 'qwerty'", error.message
  end

  def test_extension
    index = ReaPack::Index.new @dummy_path
    index.files = ['Extensions/reapack.ext']

    index.scan index.files.first, <<-IN
      @version 1.0
      @provides
        reaper_reapack.so http://example.com/$path
    IN

    expected = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1">
  <category name="Extensions">
    <reapack name="reapack.ext" type="extension">
      <version name="1.0">
        <source file="reaper_reapack.so">http://example.com/reaper_reapack.so</source>
      </version>
    </reapack>
  </category>
</index>
    XML

    index.write!
    assert_equal expected, File.read(index.path)
  end

  def test_effect
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['Dynamics/super_compressor.jsfx']

    index.scan index.files.first, '@version 1.0'

    expected = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1">
  <category name="Dynamics">
    <reapack name="super_compressor.jsfx" type="effect">
      <version name="1.0">
        <source>http://host/Dynamics/super_compressor.jsfx</source>
      </version>
    </reapack>
  </category>
</index>
    XML

    index.write!
    assert_equal expected, File.read(index.path)
  end

  def test_data
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['Grooves/sws.data', 'Grooves/sws/test.mid']

    index.scan index.files.first, "@version 1.0\n@provides sws/*.mid"

    expected = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1">
  <category name="Grooves">
    <reapack name="sws.data" type="data">
      <version name="1.0">
        <source file="sws/test.mid">http://host/Grooves/sws/test.mid</source>
      </version>
    </reapack>
  </category>
</index>
    XML

    index.write!
    assert_equal expected, File.read(index.path)
  end

  def test_theme
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['Themes/Default_4.0 + width.theme']

    index.scan index.files.first, <<-IN
    @version 1.0
    @provides Default_4.0_width.ReaperThemeZip http://stash.reaper.fm/27310/$path
    IN

    expected = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1">
  <category name="Themes">
    <reapack name="Default_4.0 + width.theme" type="theme">
      <version name="1.0">
        <source file="Default_4.0_width.ReaperThemeZip">http://stash.reaper.fm/27310/Default_4.0_width.ReaperThemeZip</source>
      </version>
    </reapack>
  </category>
</index>
    XML

    index.write!
    assert_equal expected, File.read(index.path)
  end

  def test_langpack
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['Translations/French.ReaperLangPack']

    index.scan index.files.first, <<-IN
    @version 1.0
    IN

    expected = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1">
  <category name="Translations">
    <reapack name="French.ReaperLangPack" type="langpack">
      <version name="1.0">
        <source>http://host/Translations/French.ReaperLangPack</source>
      </version>
    </reapack>
  </category>
</index>
    XML

    index.write!
    assert_equal expected, File.read(index.path)
  end

  def test_webinterface
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['Web Interfaces/Test.www']

    index.scan index.files.first, <<-IN
    @version 1.0
    @provides test.html http://host/test.html
    IN

    expected = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1">
  <category name="Web Interfaces">
    <reapack name="Test.www" type="webinterface">
      <version name="1.0">
        <source file="test.html">http://host/test.html</source>
      </version>
    </reapack>
  </category>
</index>
    XML

    index.write!
    assert_equal expected, File.read(index.path)
  end
end

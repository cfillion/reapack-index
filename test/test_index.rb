require File.expand_path '../helper', __FILE__

class TestIndex < MiniTest::Test
  def setup
    @real_path = File.expand_path '../data/index.xml', __FILE__
    @dummy_path = Dir::Tmpname.create('index.xml') {|path| path }

    @commit = '399f5609cff3e6fd92b5542d444fbf86da0443c6'
  end

  def teardown
    File.delete @dummy_path if File.exist? @dummy_path
  end

  def test_type_of
    assert_nil ReaPack::Index.type_of('src/main.cpp')

    assert_equal :script, ReaPack::Index.type_of('Track/instrument_track.lua')
    assert_equal :script, ReaPack::Index.type_of('Track/instrument_track.eel')
  end

  def test_url_template
    index = ReaPack::Index.new @dummy_path
    assert_nil index.url_template

    index.url_template = 'https://get.cfillion.tk/?v=$version&f=$path'
    assert_equal 'https://get.cfillion.tk/?v=$version&f=$path', index.url_template

    index.url_template = 'https://google.com/$path'
    assert_equal 'https://google.com/$path', index.url_template

    error = assert_raises ReaPack::Index::Error do
      index.url_template = 'no path placeholder!'
    end

    assert_match '$path', error.message
    assert_equal 'https://google.com/$path', index.url_template

    index.url_template = nil
    assert_nil index.url_template
  end

  def test_url_template_unsupported_scheme
    index = ReaPack::Index.new @dummy_path

    error = assert_raises ReaPack::Index::Error do
      index.url_template = 'scp://cfillion.tk/$path'
    end

    assert_match /invalid url/i, error.message
  end

  def test_files
    index = ReaPack::Index.new @dummy_path
    assert_empty index.files

    index.files = ['a', 'b/c']
    assert_equal ['a', 'b/c'], index.files
  end

  def test_validate_standalone
    refute_nil ReaPack::Index.validate_file @real_path # not a valid script
  end

  def test_validate_noindex
    assert_nil ReaPack::Index.validate_file \
      File.expand_path '../data/noindex.lua', __FILE__
  end

  def test_read
    index = ReaPack::Index.new @real_path

    assert_equal 1, index.version
    assert_equal @commit, index.commit
  end

  def test_new
    index = ReaPack::Index.new @dummy_path

    assert_equal 1, index.version
    assert_nil index.commit

    assert_equal true, index.modified?
    assert_equal "empty index", index.changelog

    index.write @dummy_path
    assert_equal true, index.modified?

    index.write!
    assert_equal false, index.modified?
  end

  def test_save
    index = ReaPack::Index.new @real_path

    index.write @dummy_path
    assert_equal File.read(@real_path), File.read(@dummy_path)
  end

  def test_mkdir
    path = File.expand_path '../dummy_dir/test.xml', __FILE__
    dirname = File.dirname path

    refute File.exist? dirname

    index = ReaPack::Index.new path
    index.write!

    assert File.exist? dirname
  ensure
    FileUtils.rm_r dirname if File.exist? dirname
  end

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
        <source platform="all">http://host/Category/Path/Instrument%20Track.lua</source>
      </version>
    </reapack>
  </category>
</index>
    XML

    assert_equal expected, File.read(index.path)
  end

  def test_default_category
    index = ReaPack::Index.new @dummy_path
    index.files = ['script.lua', 'Hello/World']
    index.url_template = 'http://host/$path'

    index.scan index.files.first, <<-IN
      @version 1.0
      @provides Hello/World
    IN

    index.write!
    result = File.read index.path
    assert_match '<category name="Other">', result
    assert_match 'file="Hello/World"', result
  end

  def test_edit_version_amend_off
    index = ReaPack::Index.new @real_path
    assert_equal false, index.amend

    index.url_template = 'http://google.com/$path'
    index.files = ['Category Name/Hello World.lua']

    index.scan index.files.first, <<-IN
      @version 1.0
      @changelog New Changelog!
    IN

    assert_equal false, index.modified?
    assert_empty index.changelog
  end

  def test_edit_version_amend_on
    index = ReaPack::Index.new @real_path
    index.amend = true
    assert_equal true, index.amend

    index.time = Time.now # must not be used
    index.url_template = 'http://google.com/$path'
    index.files = ['Category Name/Hello World.lua']

    index.scan index.files.first, <<-IN
      @version 1.0
      @changelog Intermediate Changelog!
    IN

    # when reindexing the same file a second time,
    # the changelog is expected to only have been bumped a single time
    index.scan index.files.first, <<-IN
      @version 1.0
      @changelog New Changelog!
    IN

    assert index.modified?, 'index is not modified'
    assert_equal '1 modified package, 1 modified version', index.changelog

    expected = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" commit="#{@commit}">
  <category name="Category Name">
    <reapack name="Hello World.lua" type="script">
      <version name="1.0">
        <changelog><![CDATA[New Changelog!]]></changelog>
        <source platform="all">http://google.com/Category%20Name/Hello%20World.lua</source>
      </version>
    </reapack>
  </category>
</index>
    XML

    index.write @dummy_path
    assert_equal expected, File.read(@dummy_path)
  end

  def test_edit_version_amend_unmodified
    index = ReaPack::Index.new @real_path
    index.amend = true

    index.url_template = 'https://google.com/$path'
    index.files = ['Category Name/Hello World.lua']

    index.scan index.files.first, <<-IN
      @version 1.0
      @author cfillion
      @changelog Fixed a division by zero error.
    IN

    assert_equal false, index.modified?
    assert_empty index.changelog
  end

  def test_file_unlisted
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://google.com/$path'

    error = assert_raises ReaPack::Index::Error do
     index.scan 'unlisted.lua', '@version 1.0'
    end

    assert_equal 'unlisted.lua: No such file or directory', error.message

    expected = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1"/>
    XML

    index.write!
    assert_equal expected, File.read(index.path)
  end

  def test_make_url_without_template
    index = ReaPack::Index.new @dummy_path
    index.files = ['script.lua']

    error = assert_raises ReaPack::Index::Error do
     index.scan index.files.first, '@version 1.0'
    end

    assert_match /url template is unset/i, error.message
  end

  def test_make_url_defaut_branch
    index = ReaPack::Index.new @dummy_path
    index.files = ['Category/script.lua']
    index.url_template = 'http://host/$commit/$path'

    index.commit = nil

    index.scan index.files.first, '@version 1.0'

    index.write!
    assert_match 'http://host/master/Category/script.lua', File.read(index.path)
  end

  def test_make_url_commit
    index = ReaPack::Index.new @dummy_path
    index.files = ['Category/script.lua']
    index.url_template = 'http://host/$commit/$path'
    index.commit = @commit

    index.scan index.files.first, '@version 1.0'

    index.write!
    assert_match "http://host/#{@commit}/Category/script.lua",
      File.read(index.path)
  end

  def test_missing_version
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['test.lua']

    error = assert_raises ReaPack::Index::Error do
      index.scan index.files.first, 'no version tag here'
    end

    assert_match 'missing tag "version"', error.message
  end

  def test_changelog_boolean
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['test.lua']

    error = assert_raises ReaPack::Index::Error do
      index.scan index.files.first, <<-IN
        @version 1.0
        @changelog
      IN
    end

    assert_match 'invalid value for tag "changelog"', error.message
  end

  def test_author
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['Category/script.lua']

    index.scan index.files.first, <<-IN
      @version 1.0
      @author cfillion
    IN

    index.write!
    assert_match '<version name="1.0" author="cfillion">', File.read(index.path)
  end

  def test_author_boolean
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['test.lua']

    error = assert_raises ReaPack::Index::Error do
      index.scan index.files.first, <<-IN
        @version 1.0
        @author
      IN
    end

    assert_match 'invalid value for tag "author"', error.message
  end

  def test_author_multiline
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['test.lua']

    error = assert_raises ReaPack::Index::Error do
      index.scan index.files.first, <<-IN
        @version 1.0
        @author
          hello
          world
      IN
    end

    assert_equal 'invalid metadata: invalid value for tag "author"', error.message
  end

  def test_provides
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'

    index.files = [
      'Category/script.lua',
      'Resources/unicode.dat',
      'Category/test.png',
    ]

    index.scan index.files.first, <<-IN
      @version 1.0
      @provides
        ../Resources/unicode.dat
        test.png
    IN

    expected = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1">
  <category name="Category">
    <reapack name="script.lua" type="script">
      <version name="1.0">
        <source platform="all">http://host/Category/script.lua</source>
        <source platform="all" file="../Resources/unicode.dat">http://host/Resources/unicode.dat</source>
        <source platform="all" file="test.png">http://host/Category/test.png</source>
      </version>
    </reapack>
  </category>
</index>
    XML

    index.write!
    assert_equal expected, File.read(index.path)
  end

  def test_provides_not_found
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['Category/script.lua']

    error = assert_raises ReaPack::Index::Error do
     index.scan index.files.first, <<-IN
       @version 1.0
       @provides
         test.png
     IN
    end

    assert_equal 'Category/test.png: No such file or directory', error.message
  end

  def test_provides_duplicate
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'

    error = assert_raises ReaPack::Index::Error do
     index.scan 'script.lua', <<-IN
       @version 1.0
       @provides
         test.png
         test.png http://url.com
     IN
    end

    assert_match 'invalid value for tag "provides": duplicate file (test.png)',
      error.message
  end

  def test_provides_duplicate_platforms
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['script.lua', 'test.png', 'test.png']

    index.scan index.files.first, <<-IN
      @version 1.0
      @provides
        [windows] test.png
        [darwin] test.png
    IN
  end

  def test_invalid_platform
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'

    error = assert_raises ReaPack::Index::Error do
      index.scan 'test.lua', <<-IN
        @version 1.0
        @provides
          [hello] test.png
      IN
    end

    assert_match 'invalid value for tag "provides": invalid platform hello',
      error.message
  end

  def test_provides_platform
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'

    index.files = [
      'Category/script.lua',
      'Category/winall.png',
      'Category/win32bit.png',
      'Category/win64bit.png',
      'Category/osxall.png',
      'Category/osx32bit.png',
      'Category/osx64bit.png',
    ]

    index.scan index.files.first, <<-IN
      @version 1.0
      @provides
        [windows] winall.png
        [win32]  win32bit.png
        [win64]win64bit.png
         [ darwin ] osxall.png
        [darwin32] osx32bit.png
        [darwin64] osx64bit.png
    IN

    expected = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1">
  <category name="Category">
    <reapack name="script.lua" type="script">
      <version name="1.0">
        <source platform="all">http://host/Category/script.lua</source>
        <source platform="windows" file="winall.png">http://host/Category/winall.png</source>
        <source platform="win32" file="win32bit.png">http://host/Category/win32bit.png</source>
        <source platform="win64" file="win64bit.png">http://host/Category/win64bit.png</source>
        <source platform="darwin" file="osxall.png">http://host/Category/osxall.png</source>
        <source platform="darwin32" file="osx32bit.png">http://host/Category/osx32bit.png</source>
        <source platform="darwin64" file="osx64bit.png">http://host/Category/osx64bit.png</source>
      </version>
    </reapack>
  </category>
</index>
    XML

    index.write!
    assert_equal expected, File.read(index.path)
  end

  def test_main_platform
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['Category/script.lua']

    index.scan index.files.first, <<-IN
      @version 1.0
      @provides
        [darwin] .
        [win64] script.lua
    IN

    expected = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1">
  <category name="Category">
    <reapack name="script.lua" type="script">
      <version name="1.0">
        <source platform="darwin">http://host/Category/script.lua</source>
        <source platform="win64">http://host/Category/script.lua</source>
      </version>
    </reapack>
  </category>
</index>
    XML

    index.write!
    assert_equal expected, File.read(index.path)
  end

  def test_provides_custom_url
    index = ReaPack::Index.new @dummy_path
    index.files = ['Category/script.lua']

    index.scan index.files.first, <<-IN
      @version 1.0
      @provides
        script.lua http://google.com/download/$commit/$version/$path
    IN

    index.write!
    assert_match 'http://google.com/download/master/1.0/Category/script.lua',
      File.read(index.path)
  end

  def test_provides_spaces
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['Category/hello world.lua']

    index.scan index.files.first, <<-IN
      @version 1.0
      @provides
        hello world.lua
    IN

    index.write!

    result = File.read @dummy_path
    assert_match 'hello world.lua', result
  end

  def test_provides_empty
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['Category/hello.lua']

    index.scan index.files.first, <<-IN
      @version 1.0
      @provides
    IN
  end

  def test_remove
    index = ReaPack::Index.new @real_path

    index.remove 'Category Name/Hello World.lua'

    assert_equal true, index.modified?
    assert_equal '1 removed package', index.changelog

    expected = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" commit="#{@commit}"/>
    XML

    index.write @dummy_path
    assert_equal expected, File.read(@dummy_path)
  end

  def test_remove_inexistant
    index = ReaPack::Index.new @real_path

    index.remove '404.lua'

    assert_equal false, index.modified?
    assert_empty index.changelog
  end

  def test_noindex
    index = ReaPack::Index.new @real_path

    index.scan 'script.lua', '@noindex'

    assert_equal false, index.modified?
  end

  def test_noindex_remove
    index = ReaPack::Index.new @real_path

    index.scan 'Category Name/Hello World.lua', '@noindex'

    assert_equal true, index.modified?
    assert_equal '1 removed package', index.changelog

    expected = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1" commit="#{@commit}"/>
    XML

    index.write @dummy_path
    assert_equal expected, File.read(@dummy_path)
  end

  def test_version_time
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['Category/script.lua']
    index.time = Time.new 2016, 2, 11, 20, 16, 40, -5 * 3600

    index.scan index.files.first, '@version 1.0'

    index.write!
    assert_match '<version name="1.0" time="2016-02-12T01:16:40Z">',
      File.read(index.path)
  end

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
        <source platform="all" file="reaper_reapack.so">http://example.com/reaper_reapack.so</source>
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
        <source platform="all">http://host/Dynamics/super_compressor.jsfx</source>
      </version>
    </reapack>
  </category>
</index>
    XML

    index.write!
    assert_equal expected, File.read(index.path)
  end

  def test_sort_tags
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['Hello/world.lua']

    index.description = 'hello'

    index.scan index.files.first, '@version 1.0'

    index.write!
    assert_match /<category.+<metadata>/m, File.read(index.path)
  end

  def test_sort_categories
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['zebra/agent.lua', 'bee/agent.lua']

    index.scan index.files.first, '@version 1.0'
    index.scan index.files.last, '@version 1.0'

    index.write!
    assert_match /bee.+zebra/m, File.read(index.path)
  end

  def test_sort_packages
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['zebra.lua', 'bee.lua']

    index.scan index.files.first, '@version 1.0'
    index.scan index.files.last, '@version 1.0'

    index.write!
    assert_match /bee.+zebra/m, File.read(index.path)
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

require File.expand_path '../../helper', __FILE__

TestIndex ||= Class.new Minitest::Test

class TestIndex::Provides < Minitest::Test
  include IndexHelper

  def test_simple
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path?$package'

    index.files = [
      'Category/script.lua',
      'Resources/unicode.dat',
      'Category/test.png',
    ]

    index.scan index.files.first, <<-IN
      @version 1.0
      @provides
        [windows] ../Resources/unicode.dat
        test.png
    IN

    expected = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1">
  <category name="Category">
    <reapack name="script.lua" type="script">
      <version name="1.0">
        <source main="main">http://host/Category/script.lua?Category/script.lua</source>
        <source platform="windows" file="../Resources/unicode.dat">http://host/Resources/unicode.dat?Category/script.lua</source>
        <source file="test.png">http://host/Category/test.png?Category/script.lua</source>
      </version>
    </reapack>
  </category>
</index>
    XML

    index.write!
    assert_equal expected, File.read(index.path)
  end

  def test_not_found
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

    assert_equal "file not found 'test.png'", error.message
  end

  def test_mainfile_platform
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
        <source main="main" platform="darwin">http://host/Category/script.lua</source>
        <source main="main" platform="win64">http://host/Category/script.lua</source>
      </version>
    </reapack>
  </category>
</index>
    XML

    index.write!
    assert_equal expected, File.read(index.path)
  end

  def test_custom_url
    index = ReaPack::Index.new @dummy_path
    index.files = ['Category/script.lua']

    index.scan index.files.first, <<-IN
      @version 1.0
      @provides
        script.lua http://google.com/download/$commit/$version/$path
        /root http://google.com/download/$commit/$version/$path
    IN

    index.write!

    xml = File.read index.path
    assert_match 'http://google.com/download/master/1.0/Category/script.lua', xml
    assert_match 'file="../root"', xml
  end

  def test_empty_tag
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['Category/hello.lua']

    error = assert_raises ReaPack::Index::Error do
      index.scan index.files.first, <<-IN
        @version 1.0
        @provides
      IN
    end
  end

  def test_glob
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = [
      'Category/script.lua',
      'Category/Data/a.dat',
      'Category/Data/b.dat',
      'Category/test.txt',
      'Category/test/d.dat', # should not be matched by test*
    ]

    index.scan index.files.first, <<-IN
      @version 1.0
      @provides
        [windows] Data/{a,b}.*
        test*
    IN

    expected = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1">
  <category name="Category">
    <reapack name="script.lua" type="script">
      <version name="1.0">
        <source main="main">http://host/Category/script.lua</source>
        <source platform="windows" file="Data/a.dat">http://host/Category/Data/a.dat</source>
        <source platform="windows" file="Data/b.dat">http://host/Category/Data/b.dat</source>
        <source file="test.txt">http://host/Category/test.txt</source>
      </version>
    </reapack>
  </category>
</index>
    XML

    index.write!
    assert_equal expected, File.read(index.path)
  end

  def test_duplicate
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['cat/script.lua', 'cat/test.png']

    error = assert_raises ReaPack::Index::Error do
     index.scan index.files.first, <<-IN
       @version 1.0
       @provides
         test.png
         test.png http://url.com
     IN
    end

    assert_equal "duplicate file 'cat/test.png'", error.message
  end

  def test_conflicts
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['cat/script1.lua', 'cat/script2.lua', 'cat/script3.lua',
                   'cat/file1', 'cat/file2']

    index.scan index.files[0], <<-IN
      @version 1.0
      @provides file1
    IN

    error = assert_raises ReaPack::Index::Error do
     index.scan index.files[1], <<-IN
       @version 1.0
       @provides
         file1
         file2
     IN
    end

    assert_equal "'cat/file1' conflicts with 'cat/script1.lua'",
      error.message

    # did script2.lua did leave any trace behind?
    index.scan index.files[2], <<-IN
      @version 1.0
      @provides file2
    IN
  end

  def test_duplicate_other_package
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['cat/script1.lua', 'cat/script2.lua']

    index.scan index.files.first, <<-IN
      @version 1.0
    IN

    error = assert_raises ReaPack::Index::Error do
     index.scan index.files.last, <<-IN
       @version 1.0
       @provides script1.lua
     IN
    end

    assert_equal "'cat/script1.lua' conflicts with 'cat/script1.lua'",
      error.message
  end

  def test_duplicate_cross_directory
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['Category1/script1.lua', 'Category2/script2.lua',
                   'Category1/file']

    index.scan index.files[0], <<-IN
      @version 1.0
      @provides file
    IN

    error = assert_raises ReaPack::Index::Error do
     index.scan index.files[1], <<-IN
       @version 1.0
       @provides ../Category1/file
     IN
    end

    assert_equal "'Category1/file' conflicts with 'Category1/script1.lua'",
      error.message
  end

  def test_conflict_with_existing
    File.write @dummy_path, <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1">
  <category name="Other">
    <reapack name="test1.lua" type="script">
      <version name="1.0">
        <source file="background.png">http://irrelevant</source>
      </version>
    </reapack>
  </category>
</index>
    XML

    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['Other/test2.lua', 'Other/background.png']

    error = assert_raises ReaPack::Index::Error do
      index.scan index.files.first, <<-IN
        @version 1.0
        @provides background.png
      IN
    end

    assert_equal "'Other/background.png' conflicts with 'Other/test1.lua'",
      error.message
  end

  def test_same_file_cross_type
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['script.lua', 'file', 'effect.jsfx']

    index.scan index.files.first, <<-IN
      @version 1.0
      @provides file
    IN

    index.scan index.files.last, <<-IN
      @version 1.0
      @provides file
    IN
  end

  def test_main
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = [
      'Category/script.lua',
      'Category/a.dat',
      'Category/b.dat',
      'Category/c.dat',
    ]

    index.scan index.files.first, <<-IN
      @version 1.0
      @provides
        [main] a.dat
        [nomain] .
        [nomain] b.dat
        [main=midi_editor] c.dat
    IN

    expected = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1">
  <category name="Category">
    <reapack name="script.lua" type="script">
      <version name="1.0">
        <source main="main" file="a.dat">http://host/Category/a.dat</source>
        <source>http://host/Category/script.lua</source>
        <source file="b.dat">http://host/Category/b.dat</source>
        <source main="midi_editor" file="c.dat">http://host/Category/c.dat</source>
      </version>
    </reapack>
  </category>
</index>
    XML

    index.write!
    assert_equal expected, File.read(index.path)
  end

  def test_main_self
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['Category/script.lua']

    index.scan index.files.first, <<-IN
      @version 1.0
      @provides .
    IN

    index.write!
    assert_match 'main="main"', File.read(index.path)
  end

  def test_metapackage_override
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['Category/script.lua']

    index.scan index.files.first, <<-IN
      @metapackage
      @version 1.0
      @provides .
    IN

    index.write!
    contents = File.read index.path

    refute_match 'main="main"', contents
    assert_match '<source>http://host/Category/script.lua</source>', contents
  end

  def test_rename_target
    index = ReaPack::Index.new @dummy_path
    index.files = ['Category/source.lua', 'Category/source.png',
                   'Category/source1.jpg', 'Category/source2.jpg',
                   'Category/sub/source.txt']
    index.url_template = 'http://host/$path'

    index.scan index.files.first, <<-IN
      @version 1.0
      @provides
        source.lua > target.lua
        source.png > ./target.png
        source*.jpg > target_dir/
        source*.jpg > ../target_dir/
        sub/source.txt > .
    IN

    index.write!

    xml = File.read index.path

    assert_match 'file="target.lua"', xml
    assert_match 'file="./target.png"', xml
    assert_match 'file="target_dir/source1.jpg"', xml
    assert_match 'file="target_dir/source2.jpg"', xml
    assert_match 'file="../target_dir/source1.jpg"', xml
    assert_match 'file="../target_dir/source2.jpg"', xml
    assert_match 'file="./source.txt"', xml
    refute_match 'file="source.png"', xml

    assert_equal 1,
      xml.scan(/#{Regexp.quote('http://host/Category/source.lua')}/).count
    assert_match 'http://host/Category/source.png', xml
  end

  def test_rename_target_conflict
    index = ReaPack::Index.new @dummy_path

    # target.lua is not in the same directory
    index.files = ['Category/target.lua', 'Category/sub/target.lua']
    index.url_template = 'http://host/$path'

    error = assert_raises ReaPack::Index::Error do
      index.scan index.files.first, <<-IN
        @version 1.0
        @provides . > target.lua
        @provides sub/target.lua > ./
      IN
    end
    assert_equal "duplicate file 'Category/target.lua'", error.message
  end

  def test_rename_target_no_wrong_conflict
    index = ReaPack::Index.new @dummy_path

    # target.lua is not in the same directory
    index.files = ['Category/s1.lua', 'target.lua', 'Category/s2.lua']
    index.url_template = 'http://host/$path'

    index.scan index.files.first, <<-IN
      @version 1.0
      @provides . > target.lua
    IN

    index.scan index.files.last, <<-IN
      @version 1.0
      @provides ../target.lua
    IN
  end

  def test_rename_target_same_name
    index = ReaPack::Index.new @dummy_path
    index.files = ['Category/script.lua']
    index.url_template = 'http://host/$path'

    index.scan index.files.first, <<-IN
      @version 1.0
      @provides . > script.lua
    IN

    index.write!
    refute_match 'file=', File.read(index.path)
  end
end

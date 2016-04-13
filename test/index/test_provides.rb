require File.expand_path '../../helper', __FILE__

TestIndex ||= Class.new MiniTest::Test

class TestIndex::Provides < MiniTest::Test
  include IndexHelper

  def test_simple
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

  def test_platform
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

    assert_match %q{invalid value for tag "provides": invalid platform 'hello'},
      error.message
  end

  def test_custom_url
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

  def test_filename_spaces
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
        [windows] Data/*
        test*
    IN

    expected = <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1">
  <category name="Category">
    <reapack name="script.lua" type="script">
      <version name="1.0">
        <source platform="all">http://host/Category/script.lua</source>
        <source platform="windows" file="Data/a.dat">http://host/Category/Data/a.dat</source>
        <source platform="windows" file="Data/b.dat">http://host/Category/Data/b.dat</source>
        <source platform="all" file="test.txt">http://host/Category/test.txt</source>
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
    index.files = ['script.lua', 'test.png']

    error = assert_raises ReaPack::Index::Error do
     index.scan index.files.first, <<-IN
       @version 1.0
       @provides
         test.png
         test.png http://url.com
     IN
    end

    assert_equal "duplicate file 'test.png'", error.message
  end

  def test_conflicts
    index = ReaPack::Index.new @dummy_path
    index.url_template = 'http://host/$path'
    index.files = ['script1.lua', 'script2.lua', 'script3.lua',
                   'file1', 'file2']

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

    assert_equal "'file1' conflicts with 'script1.lua'",
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
    index.files = ['script1.lua', 'script2.lua']

    index.scan index.files.first, <<-IN
      @version 1.0
    IN

    error = assert_raises ReaPack::Index::Error do
     index.scan index.files.last, <<-IN
       @version 1.0
       @provides script1.lua
     IN
    end

    assert_equal "'script1.lua' conflicts with 'script1.lua'",
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
end

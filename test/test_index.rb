require File.expand_path '../helper', __FILE__

class TestIndex < MiniTest::Test
  include IndexHelper

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
      index.url_template = 'test' # no path placeholder!
    end

    assert_match "missing $path placeholder in 'test'", error.message
    assert_equal 'https://google.com/$path', index.url_template

    index.url_template = nil
    assert_nil index.url_template
  end

  def test_url_template_unsupported_scheme
    index = ReaPack::Index.new @dummy_path

    error = assert_raises ReaPack::Index::Error do
      index.url_template = 'scp://cfillion.tk/$path'
    end

    assert_match /invalid template/i, error.message
  end

  def test_file_list
    index = ReaPack::Index.new @dummy_path
    assert_empty index.files

    index.files = ['a', 'b/c']
    assert_equal ['a', 'b/c'], index.files
  end

  def test_read
    index = ReaPack::Index.new @real_path

    assert_equal 1, index.version
    assert_equal 'f572d396fae9206628714fb2ce00f72e94f2258f', index.commit
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

  def test_make_url_defaut_branch
    index = ReaPack::Index.new @dummy_path
    index.files = ['Category/script.lua']
    index.url_template = 'http://host/$commit/$path'
    index.commit = nil

    assert_match 'http://host/master/Category/script.lua',
      index.make_url('Category/script.lua')
  end

  def test_make_url_without_template
    index = ReaPack::Index.new @dummy_path
    index.files = ['script.lua']

    assert_equal nil, index.url_template
    index.make_url 'script.lua', 'ok if explicit template'

    error = assert_raises ReaPack::Index::Error do
      index.make_url 'script.lua'
    end

    assert_match /url template/i, error.message
  end

  def test_make_url_commit
    index = ReaPack::Index.new @dummy_path
    index.files = ['Category/script.lua']
    index.url_template = 'http://host/$commit/$path'
    index.commit = @commit

    assert_equal "http://host/#{@commit}/Category/script.lua",
      index.make_url('Category/script.lua')
  end

  def test_make_url_unlisted
    index = ReaPack::Index.new @dummy_path
    index.commit = @commit
    index.url_template = 'http://google.com/$path'

    index.make_url 'unlisted.lua', 'ok with url template'

    error = assert_raises ReaPack::Index::Error do
     index.make_url 'unlisted.lua'
    end

    assert_equal "file not found 'unlisted.lua'", error.message
  end

  def test_remove
    index = ReaPack::Index.new @real_path
    index.commit = @commit

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

  def test_sort_tags
    File.write @dummy_path, <<-XML
<index>
  <metadata/>
  <category name="zebra"/>
</index>
    XML

    index = ReaPack::Index.new @dummy_path
    index.write!

    assert_match /<category.+<metadata/m, File.read(index.path)
  end

  def test_sort_categories
    File.write @dummy_path, <<-XML
<index>
  <category name="zebra"/>
  <category name="bee"/>
</index>
    XML

    index = ReaPack::Index.new @dummy_path
    index.write!

    assert_match /bee.+zebra/m, File.read(index.path)
  end

  def test_sort_packages
    File.write @dummy_path, <<-XML
<index>
  <category name="Other">
    <reapack name="zebra.lua"/>
    <reapack name="bee.lua"/>
  </category>
</index>
    XML

    index = ReaPack::Index.new @dummy_path
    index.write!

    assert_match /bee.+zebra/m, File.read(index.path)
  end
end

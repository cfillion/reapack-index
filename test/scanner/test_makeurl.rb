require File.expand_path '../../helper', __FILE__

TestScanner ||= Class.new Minitest::Test

class TestScanner::TestMakeUrl < Minitest::Test
  def setup
    @cat = Minitest::Mock.new

    @pkg = Minitest::Mock.new
    @pkg.expect :path, 'Hello/World.lua'
    @pkg.expect :path, 'Hello/World.lua'

    @ver = Minitest::Mock.new
    @ver.expect :name, '1.0'

    @cdetector = Minitest::Mock.new
    @cdetector.expect :[], nil, ['Hello/World.lua']

    @index = Minitest::Mock.new
    @index.expect :cdetector, @cdetector

    @scanner = ReaPack::Index::Scanner.new @cat, @pkg, nil, @index
    @scanner.instance_variable_set :@ver, @ver
  end

  def teardown
    [@cat, @pkg, @ver, @index, @cdetector].each {|mock| mock.verify }
  end

  def test_path
    @index.expect :files, ['Category/script.lua']
    @index.expect :url_template, '$path'
    @index.expect :commit, 'C0FF33'

    assert_equal 'Category/script.lua', @scanner.make_url('Category/script.lua')
  end

  def test_commit
    @index.expect :files, ['Hello/World.lua']
    @index.expect :url_template, '$commit'
    @index.expect :commit, 'C0FF33'

    assert_equal 'C0FF33', @scanner.make_url('Hello/World.lua')
  end

  def test_defaut_branch
    @index.expect :commit, nil

    assert_match 'master', @scanner.make_url('Category/script.lua', '$commit')
  end

  def test_version
    @index.expect :files, ['Category/script.lua']
    @index.expect :url_template, '$version'
    @index.expect :commit, 'C0FF33'

    assert_equal '1.0', @scanner.make_url('Category/script.lua')
  end

  def test_package
    @index.expect :files, ['Category/script.lua']
    @index.expect :url_template, '$package'
    @index.expect :commit, 'C0FF33'

    assert_equal 'Hello/World.lua', @scanner.make_url('Category/script.lua')
  end

  def test_without_template
    @index.expect :commit, nil
    @scanner.make_url 'script.lua', 'ok if explicit template'

    @index.expect :url_template, nil
    error = assert_raises ReaPack::Index::Error do
      @scanner.make_url 'script.lua'
    end

    assert_match /url template/i, error.message
  end

  def test_unlisted
    @index.expect :commit, nil
    @index.expect :files, []
    @index.expect :url_template, 'http://implicit/url/template'

    @scanner.make_url 'unlisted.lua', 'ok with explicit url template'

    error = assert_raises ReaPack::Index::Error do
      @scanner.make_url 'unlisted.lua'
    end

    assert_equal "file not found 'unlisted.lua'", error.message
  end

  def test_repeat
    @index.expect :files, ['Category/script.lua']
    @index.expect :url_template, '$path$path'
    @index.expect :commit, 'C0FF33'

    assert_equal 'Category/script.luaCategory/script.lua',
      @scanner.make_url('Category/script.lua')
  end
end

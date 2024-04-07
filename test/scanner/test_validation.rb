require File.expand_path '../../helper', __FILE__

TestScanner ||= Class.new Minitest::Test

class TestScanner::TestValidation < Minitest::Test
  def setup
    @pkg = Minitest::Mock.new
    @pkg.expect :type, :script
    @pkg.expect :path, 'cat/test'

    @mh = MetaHeader.new
    @mh[:version] = '1.0'

    @index = Minitest::Mock.new
    @index.expect :cdetector, ReaPack::Index::ConflictDetector.new

    @scanner = ReaPack::Index::Scanner.new nil, @pkg, @mh, @index
  end

  def test_validation
    mh_mock = Minitest::Mock.new
    mh_mock.expect :alias, nil, [Hash]
    mh_mock.expect :validate, ['first', 'second'], [Hash, false]

    @scanner.instance_variable_set :@mh, mh_mock

    error = assert_raises(ReaPack::Index::Error) { @scanner.run }

    assert_equal "first\nsecond", error.message
    mh_mock.verify
  end

  def test_version
    @mh.delete :version
    error = assert_raises(ReaPack::Index::Error) { @scanner.run }
    assert_equal "missing tag 'version'", error.message

    @mh[:version] = 'no.numbers'
    error = assert_raises(ReaPack::Index::Error) { @scanner.run }
    assert_equal "invalid value for tag 'version'", error.message

    @mh[:version] = 'v1.0'
    error = assert_raises(ReaPack::Index::Error) { @scanner.run }
    assert_equal "invalid value for tag 'version'", error.message

    @mh[:version] = true
    error = assert_raises(ReaPack::Index::Error) { @scanner.run }
    assert_equal "missing value for tag 'version'", error.message

    @mh[:version] = "hello\nworld"
    error = assert_raises(ReaPack::Index::Error) { @scanner.run }
    assert_equal "tag 'version' must be singleline", error.message

    @mh[:version] = '1.99999'
    error = assert_raises(ReaPack::Index::Error) { @scanner.run }
    assert_equal "invalid value for tag 'version': segment overflow (99999 > 65535)",
      error.message
  end

  def test_author
    @mh[:author] = true
    error = assert_raises(ReaPack::Index::Error) { @scanner.run }
    assert_equal "missing value for tag 'author'", error.message

    @mh[:author] = "hello\nworld"
    error = assert_raises(ReaPack::Index::Error) { @scanner.run }
    assert_equal "tag 'author' must be singleline", error.message
  end

  def test_changelog
    @mh[:changelog] = true
    error = assert_raises(ReaPack::Index::Error) { @scanner.run }
    assert_equal "missing value for tag 'changelog'", error.message
  end

  def test_provides
    @mh[:provides] = true
    error = assert_raises(ReaPack::Index::Error) { @scanner.run }
    assert_equal "missing value for tag 'provides'", error.message

    @mh[:provides] = '[hello] world'
    error = assert_raises(ReaPack::Index::Error) { @scanner.run }
    assert_equal "invalid value for tag 'provides': unknown option 'hello'",
      error.message
  end

  def test_index
    @mh[:noindex] = 'value'
    error = assert_raises(ReaPack::Index::Error) { @scanner.run }
    assert_equal "tag 'noindex' cannot have a value", error.message
  end

  def test_metapackage
    @mh[:metapackage] = 'value'
    error = assert_raises(ReaPack::Index::Error) { @scanner.run }
    assert_equal "tag 'metapackage' cannot have a value", error.message
  end

  def test_description
    @mh[:description] = true
    error = assert_raises(ReaPack::Index::Error) { @scanner.run }
    assert_equal "missing value for tag 'description'", error.message

    @mh[:description] = "hello\nworld"
    error = assert_raises(ReaPack::Index::Error) { @scanner.run }
    assert_equal "tag 'description' must be singleline", error.message
  end

  def test_about
    @mh[:about] = true
    error = assert_raises(ReaPack::Index::Error) { @scanner.run }
    assert_equal "missing value for tag 'about'", error.message
  end

  def test_links
    @mh[:links] = true
    error = assert_raises(ReaPack::Index::Error) { @scanner.run }
    assert_equal "missing value for tag 'links'", error.message
  end

  def test_screenshot
    @mh[:screenshot] = true
    error = assert_raises(ReaPack::Index::Error) { @scanner.run }
    assert_equal "missing value for tag 'screenshot'", error.message
  end

  def test_donation
    @mh[:donation] = true
    error = assert_raises(ReaPack::Index::Error) { @scanner.run }
    assert_equal "missing value for tag 'donation'", error.message
  end
end

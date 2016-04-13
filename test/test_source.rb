require File.expand_path '../helper', __FILE__

class TestSource < MiniTest::Test
  include XMLHelper

  def test_escape_url
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

  def test_invalid_url
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

  def test_platform
    src = ReaPack::Index::Source.new
    assert_equal :all, src.platform

    src.platform = 'windows'
    assert_equal :windows, src.platform

    src.platform = nil
    assert_equal :all, src.platform
  end

  def test_invalid_platform
    src = ReaPack::Index::Source.new

    error = assert_raises ReaPack::Index::Error do
      src.platform = :hello
    end

    assert_equal "invalid platform 'hello'", error.message
    assert_equal :all, src.platform
  end

  def test_validate_platform
    ReaPack::Index::Source.validate_platform nil
    ReaPack::Index::Source.validate_platform :windows
    ReaPack::Index::Source.validate_platform 'windows'

    assert_raises ReaPack::Index::Error do
      ReaPack::Index::Source.validate_platform :atari
    end
  end
end

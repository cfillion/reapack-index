require File.expand_path '../helper', __FILE__

class TestSource < MiniTest::Test
  include XMLHelper

  def test_escape_url
    before = make_node '<version name="1.0"/>'
    after = <<-XML
<version name="1.0">
  <source platform="all">http://files.cfillion.tk/hello%20world.lua</source>
</version>
    XML

    src = ReaPack::Index::Source.new 'http://files.cfillion.tk/./hello world.lua'
    assert_equal 'http://files.cfillion.tk/./hello world.lua', src.url

    src.make_node before

    assert_equal after.chomp, before.to_s
  end

  def test_invalid_url
    after = '<version name="1.0"/>'
    before = make_node after

    src = ReaPack::Index::Source.new 'http://hello world/'
    assert_equal 'http://hello world/', src.url

    error = assert_raises ReaPack::Index::Error do
      src.make_node before
    end

    refute_empty error.message
    assert_equal after.chomp, before.to_s
  end

  def test_file
    before = make_node '<version name="1.0"/>'
    after = <<-XML
<version name="1.0">
  <source platform="all" file="test.png">http://hello/world</source>
</version>
    XML

    src = ReaPack::Index::Source.new 'http://hello/world'
    assert_nil src.file

    src.file = 'test.png'
    assert_equal 'test.png', src.file

    src.make_node before

    assert_equal after.chomp, before.to_s
  end

  def test_platform
    src = ReaPack::Index::Source.new
    assert_equal :all, src.platform

    src.platform = 'windows'
    assert_equal :windows, src.platform

    src.platform = nil
    assert_equal :all, src.platform

    src.platform = :darwin
    assert_equal :darwin, src.platform

    error = assert_raises ReaPack::Index::Error do
      src.platform = :hello
    end

    assert_equal "invalid platform 'hello'", error.message
    assert_equal :darwin, src.platform
  end

  def test_type
    before = make_node '<version name="1.0"/>'
    after = <<-XML
<version name="1.0">
  <source platform="all" type="effect">http://hello/world</source>
</version>
    XML

    src = ReaPack::Index::Source.new 'http://hello/world'
    assert_nil src.type

    src.type = 'script'
    assert_equal :script, src.type

    src.type = nil
    assert_nil src.type

    src.type = :effect
    assert_equal :effect, src.type

    error = assert_raises ReaPack::Index::Error do
      src.type = 'jsfx'
    end

    assert_equal "invalid type 'jsfx'", error.message
    assert_equal :effect, src.type

    src.make_node before

    assert_equal after.chomp, before.to_s
  end

  def test_is_platform
    assert_equal [false, true, true, false],
      [nil, :windows, 'windows', :atari].map {|p|
        ReaPack::Index::Source.is_platform? p
      }
  end
end

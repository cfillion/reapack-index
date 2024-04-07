require File.expand_path '../helper', __FILE__

class TestChangelog < Minitest::Test
  include XMLHelper

  def test_create
    before = make_node '<source/>'
    after = <<-XML
<source>
  <changelog><![CDATA[hello]]></changelog>
</source>
XML

    cl = ReaPack::Index::Changelog.new before
    assert_empty cl.text
    assert_equal 0, before.children.size
    refute cl.modified?, 'changelog modified'

    cl.text = 'hello'
    assert cl.modified?, 'changelog not modified'
    assert_equal 'hello', cl.text

    assert_equal after.chomp, before.to_s
  end

  def test_replace
    before = make_node <<-XML
<source>
  <changelog><![CDATA[hello]]></changelog>
</source>
    XML

    after = <<-XML
<source>
  <changelog><![CDATA[world]]></changelog>
</source>
    XML

    cl = ReaPack::Index::Changelog.new before
    assert_equal 'hello', cl.text

    cl.text = 'world'
    assert cl.modified?, 'changelog not modified'

    assert_equal after.chomp, before.to_s
  end

  def test_replace_identical
    before = make_node <<-XML
<source>
  <changelog><![CDATA[test]]></changelog>
</source>
    XML

    cl = ReaPack::Index::Changelog.new before

    cl.text = 'test'
    refute cl.modified?, 'changelog is modified'
  end

  def test_remove
    before = make_node <<-XML
<source>
  <changelog><![CDATA[hello]]></changelog>
</source>
    XML

    cl = ReaPack::Index::Changelog.new before
    assert_equal 'hello', cl.text

    cl.text = String.new
    assert cl.modified?, 'changelog not modified'

    refute_match /changelog/, before.to_s
  end
end

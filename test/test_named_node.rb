require File.expand_path '../helper', __FILE__

class TestNamedNode < Minitest::Test
  include XMLHelper

  def setup
    @mock = Class.new(ReaPack::Index::NamedNode) { @tag = 'node' }
  end

  def test_no_tag_set
    @ock = Class.new ReaPack::Index::NamedNode
    assert_raises { mock.tag }
  end

  def test_create_node
    before = make_node '<parent />'

    after = <<-XML
<parent>
  <node name="name here"/>
</parent>
    XML

    instance = @mock.create 'name here', before
    assert instance.is_new?, 'instance is not new'
    assert instance.modified?, 'instance is not modified'

    assert_equal after.chomp, before.to_s
  end

  def test_from_existing_node
    before = make_node '<node name="1.0"/>'

    instance = @mock.new before
    refute instance.is_new?, 'instance is new'
    refute instance.modified?, 'instance is modified'
  end

  def test_find_one
    node = make_node '<root><node name="hello"/><node name="world"/></root>'

    instance = @mock.find_one 'hello', node
    assert_kind_of @mock, instance
    assert_equal 'hello', instance.name

    assert_nil @mock.find_one 'bacon', node
  end

  def test_find_all
    node = make_node '<root><node name="hello"/><node name="world"/></root>'

    instances = @mock.find_all node
    assert_equal 2, instances.size

    assert_kind_of @mock, instances.first
    assert_equal 'hello', instances.first.name

    assert_kind_of @mock, instances.last
    assert_equal 'world', instances.last.name
  end

  def test_fetch_existing
    node = make_node '<root><node name="hello"/></root>'

    instance = @mock.fetch 'hello', node, false
    assert_kind_of @mock, instance

    assert_nil @mock.fetch 'world', node, false
  end

  def test_fetch_create
    node = make_node '<root></root>'

    instance = @mock.fetch 'hello', node, true

    assert_kind_of @mock, instance
    assert instance.is_new?, 'instance is not new'
    assert instance.modified?, 'instance is not modified'
  end

  def test_get_null_parent
    assert_nil @mock.fetch 'hello', nil, false
  end

  def test_empty
    first = @mock.new make_node('<node/>')
    assert first.empty?, 'first is not empty'

    second = @mock.new make_node('<node><something/></node>')
    refute second.empty?, 'second is empty'
  end

  def test_remove
    node = make_node '<root><node name="test"/></root>'
    instance = @mock.find_one 'test', node

    assert_equal 1, node.children.size
    instance.remove
    assert_equal 0, node.children.size
  end

  def test_children
    node = make_node '<node name="test"><a/><b><a/></b></node>'

    instance = @mock.new node
    assert_equal node.css('> a').inspect, instance.children('a').inspect
  end
end

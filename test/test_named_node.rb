require File.expand_path '../helper', __FILE__

class TestNamedNode < MiniTest::Test
  def test_no_tag_set
    mock = Class.new ReaPack::Index::NamedNode
    assert_raises { mock.tag }
  end

  def test_find_in
    node = make_node '<root><node name="hello"/><node name="world"/></root>'
    mock = Class.new(ReaPack::Index::NamedNode) { @tag = 'node' }

    instance = mock.find_in node, 'hello'
    assert_nil mock.find_in node, 'bacon'

    assert_kind_of mock, instance
    assert_equal 'hello', instance.name
    refute instance.is_new?, 'instance is new'
    refute instance.modified?, 'instance is modified'
  end

  def test_find_all
    node = make_node '<root><node name="hello"/><node name="world"/></root>'
    mock = Class.new(ReaPack::Index::NamedNode) { @tag = 'node' }

    instances = mock.find_all node
    assert_equal 2, instances.size

    assert_kind_of mock, instances.first
    assert_equal 'hello', instances.first.name
    refute instances.first.is_new?, 'instance is new'

    assert_equal 'world', instances.last.name
  end

  def test_get_readonly
    node = make_node '<root><node name="hello"/></root>'
    mock = Class.new(ReaPack::Index::NamedNode) { @tag = 'node' }

    instance = mock.get 'hello', node, false
    assert_kind_of mock, instance

    assert_nil mock.get 'world', node, false
  end

  def test_get_create
    node = make_node '<root></root>'
    mock = Class.new(ReaPack::Index::NamedNode) { @tag = 'node' }

    instance = mock.get 'hello', node, true

    assert_kind_of mock, instance
    assert instance.is_new?, 'instance is not new'
    assert instance.modified?, 'instance is not modified'
  end

  def test_get_null_parent
    mock = Class.new(ReaPack::Index::NamedNode) { @tag = 'node' }

    assert_nil mock.get 'hello', nil, false
  end

  def test_empty
    node = make_node <<-XML
    <root>
      <node name="first"/>
      <node name="second"><something/></node>
    </root>
    XML

    mock = Class.new(ReaPack::Index::NamedNode) { @tag = 'node' }

    first = mock.find_in node, 'first'
    assert first.empty?, 'first is not empty'

    second = mock.find_in node, 'second'
    refute second.empty?, 'second is empty'
  end

  def test_remove
    node = make_node '<root><node name="test"/></root>'
    mock = Class.new(ReaPack::Index::NamedNode) { @tag = 'node' }

    instance = mock.find_in node, 'test'

    assert_equal 1, node.children.size
    instance.remove
    assert_equal 0, node.children.size
  end

  def test_children
    node = make_node '<root><node name="test"><a/><b/></root>'
    mock = Class.new(ReaPack::Index::NamedNode) { @tag = 'node' }

    instance = mock.find_in node, 'test'
    assert_equal node.css('a').inspect, instance.children('a').inspect
  end
end

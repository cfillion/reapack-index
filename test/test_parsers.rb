require File.expand_path '../helper', __FILE__

class TestParsers < MiniTest::Test
  def test_wordpress
    input = <<-IN
/**
 * Version: 1.1
 */

/**
 * Changelog:
 * v1.2 (2010-01-01)
\t+ Line 1
\t+ Line 2
 * v1.1 (2011-01-01)
\t+ Line 3
\t+ Line 4
 * v1.0 (2012-01-01)
\t+ Line 5
\t+ Line 6
 */

 Test\x97
    IN

    mh = MetaHeader.parse input
    assert_equal '1.1', mh[:version]
    refute mh.has?(:changelog)

    parser = WordpressChangelog.new mh
    parser.parse input
    assert_equal "+ Line 3\n+ Line 4", mh[:changelog]
  end

  def test_wordpress_no_date
    input = <<-IN
/**
 * Version: 1.1
 */

/**
 * Changelog:
 * v1.2
\t+ Line 1
\t+ Line 2
 * v1.1
\t+ Line 3
\t+ Line 4
 * v1.0
\t+ Line 5
\t+ Line 6
 */

 Test\x97
    IN

    mh = MetaHeader.parse input
    parser = WordpressChangelog.new mh
    parser.parse input
    assert_equal "+ Line 3\n+ Line 4", mh[:changelog]
  end

  def test_wordpress_noprefix
    input = <<-IN
--[[
Version: 1.1
--]]

--[[
Changelog:

v1.2 (2010-01-01)
\t+ Line 1
\t+ Line 2
v1.1 (2011-01-01)
\t+ Line 3
\t+ Line 4
v1.0 (2012-01-01)
\t+ Line 5

]]

 Test\x97
    IN

    mh = MetaHeader.parse input
    parser = WordpressChangelog.new mh
    parser.parse input
    assert_equal "+ Line 3\n+ Line 4", mh[:changelog]
  end
end

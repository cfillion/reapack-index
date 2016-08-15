require File.expand_path '../helper', __FILE__

class TestMetadata < MiniTest::Test
  include XMLHelper

  def test_website_link
    before = make_node '<index/>'
    after = <<-XML
<index>
  <metadata>
    <link rel="website">http://cfillion.tk</link>
  </metadata>
</index>
    XML

    md = ReaPack::Index::Metadata.new before
    assert_equal false, md.modified?
    assert_empty md.links(:website)

    link = md.push_link :website, 'http://cfillion.tk'
    assert_equal true, link.is_new?
    assert_equal true, link.modified?
    assert_equal true, md.modified?

    links = md.links :website
    assert_equal 1, links.size
    assert_equal links.first.url, links.first.name
    assert_equal 'http://cfillion.tk', links.first.url

    assert_equal false, links.first.is_new?
    assert_equal false, links.first.modified?

    assert_empty md.links(:donation)
    assert_equal after.chomp, before.to_s
  end

  def test_donation_link
    before = make_node '<index/>'
    after = <<-XML
<index>
  <metadata>
    <link rel="donation">http://cfillion.tk</link>
  </metadata>
</index>
    XML

    md = ReaPack::Index::Metadata.new before
    assert_empty md.links(:donation)

    md.push_link :donation, 'http://cfillion.tk'

    links = md.links :donation
    assert_equal 1, links.size
    assert_equal links.first.url, links.first.name
    assert_equal 'http://cfillion.tk', links.first.url

    assert_empty md.links(:website)
    assert_equal after.chomp, before.to_s
  end

  def test_screenshot_link
    before = make_node '<index/>'
    after = <<-XML
<index>
  <metadata>
    <link rel="screenshot">http://cfillion.tk</link>
  </metadata>
</index>
    XML

    md = ReaPack::Index::Metadata.new before
    assert_empty md.links(:donation)

    md.push_link :screenshot, 'http://cfillion.tk'

    links = md.links :screenshot
    assert_equal 1, links.size
    assert_equal links.first.url, links.first.name
    assert_equal 'http://cfillion.tk', links.first.url

    assert_equal after.chomp, before.to_s
  end

  def test_invalid_type
    md = ReaPack::Index::Metadata.new make_node('<index/>')

    assert_raises ArgumentError do
      md.links :hello
    end

    assert_raises ArgumentError do
      md.push_link :hello, 'world'
      assert_equal false, md.modified?
    end

    assert_raises ArgumentError do
      md.remove_link :hello, 'world'
    end
  end

  def test_link_label
    before = make_node '<index/>'
    after = <<-XML
<index>
  <metadata>
    <link rel="website" href="http://cfillion.tk/">Hello World</link>
  </metadata>
</index>
    XML

    md = ReaPack::Index::Metadata.new before
    md.push_link :website, 'Hello World', 'http://cfillion.tk/'

    links = md.links :website
    assert_equal 1, links.size
    assert_equal 'Hello World', links.first.name
    assert_equal 'http://cfillion.tk/', links.first.url

    assert_equal after.chomp, before.to_s
  end

  def test_read_links
    node = make_node <<-XML
<index version="1">
  <metadata>
    <link rel="website" href="http://cfillion.tk/" />
    <link rel="website" href="https://github.com/cfillion"></link>
    <link rel="website">http://twitter.com/cfi30</link>
    <link>http://google.com</link>
    <link />
    <link rel="donation" href="http://paypal.com">Donate</link>
    <link rel="website" href="/"></link>
  </metadata>
</index>
    XML

    md = ReaPack::Index::Metadata.new node

    links = md.links :website
    assert_equal 4, links.size
    assert_equal 'http://cfillion.tk/', links[0].name
    assert_equal links[0].name, links[0].url
    assert_equal 'https://github.com/cfillion', links[1].name
    assert_equal links[1].name, links[1].url
    assert_equal 'http://twitter.com/cfi30', links[2].name
    assert_equal links[2].name, links[2].url
    assert_equal 'http://google.com', links[3].name
    assert_equal links[3].name, links[3].url
  end

  def test_split_link
    assert_equal ['http://perdu.com'],
      ReaPack::Index::Link.split('http://perdu.com')

    assert_equal ['Hello World', 'http://perdu.com/a=b'],
      ReaPack::Index::Link.split('Hello World=http://perdu.com/a=b')

    assert_equal ['Hello World', 'http://perdu.com/a=b'],
      ReaPack::Index::Link.split('Hello World http://perdu.com/a=b')

    assert_equal ['Hello World', 'http://perdu.com/a=b'],
      ReaPack::Index::Link.split('Hello World   http://perdu.com/a=b')
  end

  def test_invalid_link
    after = '<index/>'
    before = make_node after

    md = ReaPack::Index::Metadata.new before

    error = assert_raises ReaPack::Index::Error do
      md.push_link :website, 'hello'
    end

    assert_equal "invalid link 'hello'", error.message
    assert_equal after.chomp, before.to_s
  end

  def test_remove_link
    before = make_node <<-XML
<index>
  <metadata>
    <link rel="website" href="http://cfillion.tk" />
    <link rel="website" href="http://google.com">Search</link>
    <link rel="donation" href="http://paypal.com">Donate</link>
  </metadata>
</index>
    XML

    after = '<index/>'

    md = ReaPack::Index::Metadata.new before
    assert_equal 2, md.links(:website).size
    assert_equal false, md.modified?

    md.remove_link :website, 'http://cfillion.tk'
    assert_equal 1, md.links(:website).size
    assert_equal true, md.modified?

    md.remove_link :website, 'Search'
    assert_equal 0, md.links(:website).size

    assert_equal 1, md.links(:donation).size
    md.remove_link :donation, 'Donate'
    assert_equal 0, md.links(:donation).size

    assert_equal after.chomp, before.to_s
  end

  def test_remove_link_inexistant
    md = ReaPack::Index::Metadata.new make_node('<index/>')

    error = assert_raises ReaPack::Index::Error do
      md.remove_link :website, 'hello'
    end

    assert_equal "no such website link 'hello'", error.message
  end

  def test_replace_link_url
    before = make_node <<-XML
<index>
  <metadata>
    <link rel="website" href="http://cfillion.tk"/>
    <link rel="website" href="http://cfillion.no-ip.org">Test</link>
  </metadata>
</index>
    XML

    after = <<-XML
<index>
  <metadata>
    <link rel="website">http://cfillion.tk</link>
    <link rel="website" href="http://cfillion.tk">Test</link>
  </metadata>
</index>
    XML

    md = ReaPack::Index::Metadata.new before

    link1 = md.push_link :website, 'http://cfillion.tk'
    assert_equal false, link1.is_new?
    assert_equal false, link1.modified?

    link2 = md.push_link :website, 'Test', 'http://cfillion.tk'
    assert_equal false, link2.is_new?
    assert_equal true, link2.modified?

    assert_equal after.chomp, before.to_s
  end

  def test_replace_link_name
    before = make_node <<-XML
<index>
  <metadata>
    <link rel="website" href="http://cfillion.tk">A</link>
    <link rel="website">http://google.com</link>
  </metadata>
</index>
    XML

    after = <<-XML
<index>
  <metadata>
    <link rel="website">http://cfillion.tk</link>
    <link rel="website" href="http://google.com">B</link>
  </metadata>
</index>
    XML

    md = ReaPack::Index::Metadata.new before

    # remove name
    link1 = md.push_link :website, 'http://cfillion.tk'
    assert_equal false, link1.is_new?
    assert_equal true, link1.modified?

    # insert name
    link2 = md.push_link :website, 'B', 'http://google.com'
    assert_equal false, link2.is_new?
    assert_equal true, link2.modified?

    assert_equal after.chomp, before.to_s
  end

  def test_replace_links
    before = make_node <<-XML
<index>
  <metadata>
    <link rel="website" href="http://cfillion.tk">A</link>
    <link rel="donation">http://google.com</link>
  </metadata>
</index>
    XML

    after = <<-XML
<index>
  <metadata>
    <link rel="donation">http://google.com</link>
  </metadata>
</index>
    XML

    md = ReaPack::Index::Metadata.new before
    assert_equal false, md.modified?

    md.replace_links :website do
      link1 = md.push_link :website, 'A', 'http://cfillion.tk'
    end

    assert_equal false, md.modified?

    md.replace_links :website do
    end

    assert_equal true, md.modified?
    assert_equal after.chomp, before.to_s
  end

  def test_read_about
    md = ReaPack::Index::Metadata.new make_node <<-XML
<index>
  <metadata>
    <description><![CDATA[Hello World]]></description>
  </metadata>
</index>
    XML

    assert_equal 'Hello World', md.about
  end

  def test_read_about_empty
    md = ReaPack::Index::Metadata.new make_node <<-XML
<index>
  <metadata/>
</index>
    XML

    assert_empty md.about
  end

  def test_write_about
    rtf = <<-RTF
{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 \\fswiss Helvetica;}{\\f1 Courier;}}
{\\colortbl;\\red255\\green0\\blue0;\\red0\\green0\\blue255;}
\\widowctrl\\hyphauto

{\\pard \\ql \\f0 \\sa180 \\li0 \\fi0 Hello World\\par}
}
    RTF

    before = make_node '<index/>'
    after = <<-XML
<index>
  <metadata>
    <description><![CDATA[#{rtf}]]></description>
  </metadata>
</index>
    XML

    md = ReaPack::Index::Metadata.new before
    assert_empty md.about
    assert_equal false, md.modified?

    md.about = 'Hello World'
    assert_equal true, md.modified?
    assert_equal rtf, md.about

    assert_equal after.chomp, before.to_s
  end

  def test_write_about_rtf
    rtf = <<-RTF
{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 \\fswiss Helvetica;}{\\f1 Courier;}}
{\\colortbl;\\red255\\green0\\blue0;\\red0\\green0\\blue255;}
\\widowctrl\\hyphauto

{\\pard \\ql \\f0 \\sa180 \\li0 \\fi0 Hello World\\par}
}
    RTF

    before = make_node '<index/>'
    after = <<-XML
<index>
  <metadata>
    <description><![CDATA[#{rtf}]]></description>
  </metadata>
</index>
    XML

    md = ReaPack::Index::Metadata.new before
    assert_empty md.about

    md.about = rtf
    assert_equal rtf, md.about

    assert_equal after.chomp, before.to_s
  end

  def test_replace_about
    before = make_node <<-XML
<index>
  <metadata>
    <description><![CDATA[{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 \\fswiss Helvetica;}{\\f1 Courier;}}
{\\colortbl;\\red255\\green0\\blue0;\\red0\\green0\\blue255;}
\\widowctrl\\hyphauto

{\\pard \\ql \\f0 \\sa180 \\li0 \\fi0 Hello World\\par}
}
]]></description>
  </metadata>
</index>
    XML

    after = <<-XML
<index>
  <metadata>
    <description><![CDATA[{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 \\fswiss Helvetica;}{\\f1 Courier;}}
{\\colortbl;\\red255\\green0\\blue0;\\red0\\green0\\blue255;}
\\widowctrl\\hyphauto

{\\pard \\ql \\f0 \\sa180 \\li0 \\fi0 Chunky Bacon\\par}
}
]]></description>
  </metadata>
</index>
    XML

    md = ReaPack::Index::Metadata.new before
    md.about = 'Chunky Bacon'

    assert_equal after.chomp, before.to_s
  end

  def test_remove_about
    rtf = <<-RTF
{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 \\fswiss Helvetica;}{\\f1 Courier;}}
{\\colortbl;\\red255\\green0\\blue0;\\red0\\green0\\blue255;}
\\widowctrl\\hyphauto

{\\pard \\ql \\f0 \\sa180 \\li0 \\fi0 Hello World\\par}
}
    RTF

    before = make_node <<-XML
<index>
  <metadata>
    <description><![CDATA[#{rtf}]]></description>
  </metadata>
</index>
    XML

    after = '<index/>'

    md = ReaPack::Index::Metadata.new before
    refute_empty md.about

    md.about = String.new
    assert_empty md.about
    assert_equal true, md.modified?

    assert_equal after, before.to_s
  end

  def test_set_same_about
    before = make_node <<-XML
<index>
  <metadata>
    <description><![CDATA[{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0 \\fswiss Helvetica;}{\\f1 Courier;}}
{\\colortbl;\\red255\\green0\\blue0;\\red0\\green0\\blue255;}
\\widowctrl\\hyphauto

{\\pard \\ql \\f0 \\sa180 \\li0 \\fi0 Hello World\\par}
}
]]></description>
  </metadata>
</index>
    XML

    md = ReaPack::Index::Metadata.new before
    md.about = 'Hello World'
    assert_equal false, md.modified?
  end

  def test_about_markdown_blank_before_header
    before = make_node '<index/>'
    md = ReaPack::Index::Metadata.new before
    md.about = "First Line\n# Header\n* List"

    refute_match 'Firstn Line # Header * List', before.to_s
    assert_match "\\bullet", before.to_s
  end

  def test_about_markdown_no_4_space_rule
    before = make_node '<index/>'
    md = ReaPack::Index::Metadata.new before
    md.about = "- a\n- b\n  - c\n- d"

    assert_match "\\endash", before.to_s # nested list (c)
  end

  def test_pandoc_not_found
    old_path = ENV['PATH']
    ENV['PATH'] = String.new

    md = ReaPack::Index::Metadata.new make_node('<index/>')

    error = assert_raises ReaPack::Index::Error do
      md.about = 'test'
    end

    assert_match /pandoc executable cannot be found in your PATH/i, error.message
  ensure
    ENV['PATH'] = old_path
  end
end

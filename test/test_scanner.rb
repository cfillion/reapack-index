require File.expand_path '../helper', __FILE__

class TestScanner < Minitest::Test
  include XMLHelper

  def setup
    @mock = Minitest::Mock.new

    @mh = MetaHeader.new
    @mh[:version] = '1.0'

    @doc = Nokogiri::XML <<-XML
    <category name="Hello">
      <reapack type="script" name="World.lua"/>
    </category>
    XML

    @pkg = ReaPack::Index::Package.new @doc.css('reapack').first

    @index = Minitest::Mock.new
    @index.expect :cdetector, ReaPack::Index::ConflictDetector.new
    @index.expect :url_template, 'https://google.com/$path'
    @index.expect :files, ['Hello/World.lua']
    @index.expect :commit, 'master'
    2.times { @index.expect :time, Time.at(42) }

    @scanner = ReaPack::Index::Scanner.new nil, @pkg, @mh, @index
  end

  def teardown
    @mock.verify
  end

  def test_author
    @mh[:author] = 'cfillion'
    @mock.expect :author=, nil, ['cfillion']

    @pkg.version('1.0').stub :author=, -> (arg) { @mock.author= arg } do
      @scanner.run
    end
  end

  def test_version_time
    @mock.expect :time=, nil, [Time.at(42)]

    @pkg.version('1.0').stub :time=, -> (arg) { @mock.time= arg } do
      @scanner.run
    end
  end

  def test_edit_version_amend_off
    ver = make_node '<version name="1.0"/>'
    ver.parent = @pkg.node

    @index.expect :amend, false
    @pkg.version('1.0').stub :replace_sources, -> (*) { fail 'version was altered' } do
      @scanner.run
    end
  end

  def test_edit_version_amend_on
    ver = make_node '<version name="1.0"/>'
    ver.parent = @pkg.node

    @index.expect :amend, true
    @mock.expect :replace_sources, nil
    @pkg.version('1.0').stub :replace_sources, -> (*) { @mock.replace_sources } do
      @scanner.run
    end
  end

  def test_metapackage_on
    @mh[:metapackage] = true

    error = assert_raises ReaPack::Index::Error do
      @scanner.run
    end

    assert_equal 'no files provided', error.message
  end

  def test_metapackage_off
    @mh[:metapackage] = false
    @pkg.type = ReaPack::Index::Scanner::META_TYPES.first
    @scanner.run
  end

  def test_description
    @mh[:description] = 'From the New World'
    @mock.expect :description=, nil, ['From the New World']

    @pkg.stub :description=, -> (arg) { @mock.description= arg } do
      @scanner.run
    end
  end

  def test_description_alias_rescript_name
    @mh[:reascript_name] = 'Right'
    @mh[:description] = 'Wrong'
    @mock.expect :description=, nil, ['Right']

    @pkg.stub :description=, -> (arg) { @mock.description= arg } do
      @scanner.run
    end
  end

  def test_description_alias_desc
    @mh[:desc] = 'Right'
    @mh[:description] = 'Wrong'
    @mock.expect :description=, nil, ['Right']

    @pkg.stub :description=, -> (arg) { @mock.description= arg } do
      @scanner.run
    end
  end

  def test_about
    @mh[:about] = '# Hello World'
    @mock.expect :about=, nil, ['# Hello World']

    @pkg.metadata.stub :about=, -> (arg) { @mock.about= arg } do
      @scanner.run
    end
  end

  def test_website_links
    @mh[:links] = [
      'http://cfillion.tk',
      'Label http://cfillion.tk',
    ].join "\n"

    @mock.expect :push_link, nil, [:website, 'http://cfillion.tk']
    @mock.expect :push_link, nil, [:website, 'Label', 'http://cfillion.tk']

    @pkg.metadata.stub :push_link, -> (*arg) { @mock.push_link *arg } do
      @scanner.run
    end
  end

  def test_screenshot_links
    @mh[:screenshot] = [
      'http://i.imgur.com/1.png',
      '',
      'Label http://i.imgur.com/2.png',
    ].join "\n"

    @mock.expect :push_link, nil, [:screenshot, 'http://i.imgur.com/1.png']
    @mock.expect :push_link, nil, [:screenshot, 'Label', 'http://i.imgur.com/2.png']

    @pkg.metadata.stub :push_link, -> (*arg) { @mock.push_link *arg } do
      @scanner.run
    end
  end

  def test_donation_links
    @mh[:donation] = [
      'https://www.paypal.me/cfillion',
      'Label https://www.paypal.me/cfillion',
    ].join "\n"

    @mock.expect :push_link, nil, [:donation, 'https://www.paypal.me/cfillion']
    @mock.expect :push_link, nil, [:donation, 'Label', 'https://www.paypal.me/cfillion']

    @pkg.metadata.stub :push_link, -> (*arg) { @mock.push_link *arg } do
      @scanner.run
    end
  end
end

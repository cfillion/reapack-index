require File.expand_path '../helper', __FILE__

class TestScanner < MiniTest::Test
  class TestMakeUrl < MiniTest::Test
    def setup
      @cat = MiniTest::Mock.new

      @pkg = MiniTest::Mock.new
      @pkg.expect :path, 'Hello/World.lua'
      @pkg.expect :path, 'Hello/World.lua'

      @ver = MiniTest::Mock.new
      @ver.expect :name, '1.0'

      @cdetector = MiniTest::Mock.new
      @cdetector.expect :[], nil, ['Hello/World.lua']

      @index = MiniTest::Mock.new
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
      @index.expect :url_template, '$path $path'
      @index.expect :commit, 'C0FF33'

      assert_equal 'Category/script.lua Category/script.lua',
        @scanner.make_url('Category/script.lua')
    end
  end

  class TestValidation < MiniTest::Test
    def setup
      @pkg = MiniTest::Mock.new
      @pkg.expect :type, :script
      @pkg.expect :path, 'cat/test'

      @mh = MetaHeader.new String.new
      @mh[:version] = '1.0'

      @index = MiniTest::Mock.new
      @index.expect :cdetector, ReaPack::Index::ConflictDetector.new

      @scanner = ReaPack::Index::Scanner.new nil, @pkg, @mh, @index
    end

    def test_validation
      mh_mock = MiniTest::Mock.new
      mh_mock.expect :alias, nil, [Hash]
      mh_mock.expect :validate, ['first', 'second'], [Hash]

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

    def test_screenshot
      @mh[:screenshot] = true
      error = assert_raises(ReaPack::Index::Error) { @scanner.run }
      assert_equal "missing value for tag 'screenshot'", error.message
    end
  end

  class TestRun < MiniTest::Test
    include XMLHelper

    def setup
      @mock = MiniTest::Mock.new

      @mh = MetaHeader.new String.new
      @mh[:version] = '1.0'

      @doc = Nokogiri::XML <<-XML
      <category name="Hello">
        <reapack type="script" name="World.lua"/>
      </category>
      XML

      @pkg = ReaPack::Index::Package.new @doc.css('reapack').first

      @index = MiniTest::Mock.new
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
      @pkg.type = :extension
      @scanner.run
    end

    def test_description
      @mh[:description] = 'From the New World'
      @mock.expect :description=, nil, ['From the New World']

      @pkg.stub :description=, -> (arg) { @mock.description= arg } do
        @scanner.run
      end
    end

    def test_description_alias
      @mh[:reascript_name] = 'Right'
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

    def test_about_alias_instructions
      @mh[:instructions] = '# Chunky Bacon'
      @mock.expect :about=, nil, ['# Chunky Bacon']

      @pkg.metadata.stub :about=, -> (arg) { @mock.about= arg } do
        @scanner.run
      end
    end

    def test_screenshot
      @mh[:screenshot] = [
        'http://i.imgur.com/1.png',
        'Label http://i.imgur.com/2.png',
      ].join "\n"

      @mock.expect :push_link, nil, [:screenshot, 'http://i.imgur.com/1.png']
      @mock.expect :push_link, nil, [:screenshot, 'Label', 'http://i.imgur.com/2.png']

      @pkg.metadata.stub :push_link, -> (*arg) { @mock.push_link *arg } do
        @scanner.run
      end
    end
  end
end

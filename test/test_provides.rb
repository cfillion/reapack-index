require File.expand_path '../helper', __FILE__

class TestProvides < MiniTest::Test
  def test_parse_all
    enum = ReaPack::Index::Provides.parse_each "file1\nfile2"
    assert_equal 2, enum.to_a.size
  end

  def test_filename
    names = [
      'file.txt',
      'hello world.lua',
      '[file]',
    ]

    assert_equal names,
      names.map {|l| ReaPack::Index::Provides.parse(l).file_pattern }
  end

  def test_url_template
    bucket = [
      'file http://hello/world',
      'file   https://chunky/bacon',
      'file file:///foo',
      'file scp://bar',
    ].map {|l| ReaPack::Index::Provides.parse l }

    assert_equal ['http://hello/world', 'https://chunky/bacon', 'file:///foo', nil],
      bucket.map {|line| line.url_template }

    assert_equal ['file', 'file', 'file', 'file scp://bar'],
      bucket.map {|line| line.file_pattern }
  end

  def test_platforms
    assert_equal [:windows, :win32, :win64, :darwin, :darwin32, :darwin64],
      [
        '[windows] file',
        '[win32] file',
        '[win64] file',
        '[Darwin]file',
        ' [ darwin32 ] file',
        '[win32 darwin64] file',
      ].map {|l| ReaPack::Index::Provides.parse(l).platform }
  end

  def test_types
    assert_equal [:script, :data, nil, nil],
      vals = [
        '[script] file',
        '[windows Data] file',
        '[windows] file',
        '[ windows  ] file',
      ].map {|l| ReaPack::Index::Provides.parse(l).type }

  end

  def test_main
    assert_equal [true, false, nil, false, [:main, :midi_editor, :abc]],
      [
        '[main] file',
        '[nomain] file',
        'file',
        '[main nomain] file',
        '[main=main,midi_editor,,abc] file',
      ].map {|l| ReaPack::Index::Provides.parse(l).main? }
  end

  def test_target
    l1 = ReaPack::Index::Provides.parse 'src.txt > dst.txt'
    assert_equal 'src.txt', l1.file_pattern
    assert_equal 'dst.txt', l1.target
    assert_nil l1.url_template

    l2 = ReaPack::Index::Provides.parse 'src.txt >dst.txt http://test.com'
    assert_equal 'src.txt', l2.file_pattern
    assert_equal 'dst.txt http://test.com', l2.target
    assert_nil l2.url_template
  end

  def test_invalid_options
    assert_equal ["unknown option 'HeLlO'", "unknown option 'Test'"],
      [
        '[HeLlO] file',
        '[  Test] file',
      ].map {|l|
        assert_raises ReaPack::Index::Error do
          ReaPack::Index::Provides.parse l
        end.message
      }
  end

  def test_empty_line
    assert_nil ReaPack::Index::Provides.parse(String.new)
    assert_equal 2, ReaPack::Index::Provides.parse_each("a\n\nb").to_a.size
  end
end

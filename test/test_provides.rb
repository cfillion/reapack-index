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
        '[win32, darwin64] file',
      ].map {|l| ReaPack::Index::Provides.parse(l).platform }

    error = assert_raises ReaPack::Index::Error do
      ReaPack::Index::Provides.parse '[HeLlO] file'
    end

    assert_equal "unknown option (platform or type) 'HeLlO'", error.message
  end

  def test_types
    assert_equal [:script, :data, nil, nil],
      vals = [
        '[script] file',
        '[windows,Data] file',
        '[windows] file',
        '[,windows,,] file',
      ].map {|l| ReaPack::Index::Provides.parse(l).type }

    error = assert_raises ReaPack::Index::Error do
      ReaPack::Index::Provides.parse '[, Test] file'
    end

    assert_equal "unknown option (platform or type) 'Test'", error.message
  end
end

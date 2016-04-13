require File.expand_path '../helper', __FILE__

class TestSource < MiniTest::Test
  include XMLHelper

  def test_escape_url
    before = make_node '<version name="1.0"/>'
    after = <<-XML
<version name="1.0">
  <source platform="all" file="test.lua">http://files.cfillion.tk/hello%20world.lua</source>
</version>
    XML

    src = ReaPack::Index::Source.new \
      :all, 'test.lua', 'http://files.cfillion.tk/hello world.lua'
    assert_equal 'http://files.cfillion.tk/hello world.lua', src.url

    src.make_node before

    assert_equal after.chomp, before.to_s
  end

  def test_invalid_url
    after = '<version name="1.0"/>'
    before = make_node after

    src = ReaPack::Index::Source.new :all, 'test.lua', 'http://hello world/'
    assert_equal 'http://hello world/', src.url

    error = assert_raises ReaPack::Index::Error do
      src.make_node before
    end

    refute_empty error.message
    assert_equal after.chomp, before.to_s
  end

  def test_platform
    src = ReaPack::Index::Source.new
    assert_equal :all, src.platform

    src.platform = 'windows'
    assert_equal :windows, src.platform

    src.platform = nil
    assert_equal :all, src.platform
  end

  def test_invalid_platform
    src = ReaPack::Index::Source.new

    error = assert_raises ReaPack::Index::Error do
      src.platform = :hello
    end

    assert_equal "invalid platform 'hello'", error.message
    assert_equal :all, src.platform
  end

  def test_validate_platform
    ReaPack::Index::Source.validate_platform nil
    ReaPack::Index::Source.validate_platform :windows
    ReaPack::Index::Source.validate_platform 'windows'

    assert_raises ReaPack::Index::Error do
      ReaPack::Index::Source.validate_platform :atari
    end
  end
end

class TestSourceCollection < MiniTest::Test
  def test_unique
    sc = ReaPack::Index::SourceCollection.new
    sc['pkg'].push :all, 'file1.lua'
    sc['pkg'].push :all, 'file2.lua'

    assert_nil sc.conflicts('pkg')
    assert_nil sc.conflicts
  end

  def test_duplicates
    sc = ReaPack::Index::SourceCollection.new
    sc['pkg'].push :all, 'file1.lua'
    sc['pkg'].push :all, 'file1.lua'
    sc['pkg'].push :all, 'file2.lua'
    sc['pkg'].push :all, 'file2.lua'

    assert_equal ["duplicate file 'file1.lua'", "duplicate file 'file2.lua'"],
      sc.conflicts('pkg')
  end

  def test_same_platform
    sc = ReaPack::Index::SourceCollection.new
    sc['test'].push :windows, 'file.lua'
    sc['test'].push :windows, 'file.lua'

    assert_equal ["duplicate file 'file.lua' on windows"], sc.conflicts
  end

  def test_unmatching_platform
    sc = ReaPack::Index::SourceCollection.new
    sc['test'].push :darwin, 'file.lua'
    sc['test'].push :windows, 'file.lua'

    assert_nil sc.conflicts
  end

  def test_subplatform
    sc = ReaPack::Index::SourceCollection.new
    sc['test'].push :all, 'file.lua'
    sc['test'].push :windows, 'file.lua'

    assert_equal ["duplicate file 'file.lua' on windows"], sc.conflicts
  end

  def test_subsubplatform
    sc = ReaPack::Index::SourceCollection.new
    sc['test'].push :all, 'file.lua'
    sc['test'].push :win32, 'file.lua'

    assert_equal ["duplicate file 'file.lua' on win32"], sc.conflicts
  end

  def test_conflicts
    sc = ReaPack::Index::SourceCollection.new
    sc['package1.lua'].push :all, 'file1.lua'

    sc['package2.lua'].push :all, 'file1.lua'
    sc['package2.lua'].push :all, 'file2.lua'

    sc['package3.lua'].push :windows, 'file2.lua'

    sc['package4.lua'].push :darwin, 'file1.lua'

    assert_nil sc.conflicts('not_specified.lua'), 'id = not_specified'

    assert_equal ["'file1.lua' conflicts with 'package2.lua'"],
      sc.conflicts('package1.lua'), 'id = package1'

    assert_equal ["'file1.lua' conflicts with 'package1.lua'",
                  "'file2.lua' conflicts with 'package3.lua' on windows"],
      sc.conflicts('package2.lua'), 'id = package2'

    assert_equal ["'file2.lua' conflicts with 'package2.lua'"],
      sc.conflicts('package3.lua'), 'id = package3'

    # this conflict might happen on every platform,
    # so it should not be reported it as darwin-only
    assert_equal ["'file1.lua' conflicts with 'package1.lua'"],
      sc.conflicts('package4.lua'), 'id = package4'
  end

  def test_conflicts_bidirectional
    sc1 = ReaPack::Index::SourceCollection.new
    sc1['a'].push :all, 'file.lua'
    sc1['b'].push :windows, 'file.lua'

    assert_equal ["'file.lua' conflicts with 'b' on windows"],
      sc1.conflicts('a'), 'id = a'
    assert_equal ["'file.lua' conflicts with 'a'"], sc1.conflicts('b'), 'id = b'

    sc2 = ReaPack::Index::SourceCollection.new
    sc2['b'].push :windows, 'file.lua'
    sc2['a'].push :all, 'file.lua'

    assert_equal sc1.conflicts('a'), sc2.conflicts('a')
    assert_equal sc1.conflicts('b'), sc2.conflicts('b')
  end

  def test_conflicts_platform_selection
    sc1 = ReaPack::Index::SourceCollection.new
    sc1['a'].push :all, 'file.lua'
    sc1['b'].push :windows, 'file.lua'
    sc1['c'].push :win32, 'file.lua'

    assert_equal ["'file.lua' conflicts with 'b' on windows"],
      sc1.conflicts('a'), 'id = a'
  end

  def test_duplicate_platform_selection
    sc = ReaPack::Index::SourceCollection.new
    sc['test'].push :windows, 'file.lua'
    sc['test'].push :all, 'file.lua'
    assert_equal ["duplicate file 'file.lua' on windows"], sc.conflicts

    sc['test'].push :all, 'file.lua'
    assert_equal ["duplicate file 'file.lua'"], sc.conflicts
  end

  def test_platform_same_level
    sc1 = ReaPack::Index::SourceCollection.new
    sc1['test'].push :all, 'file.lua'
    sc1['test'].push :win32, 'file.lua' # win32 first
    sc1['test'].push :darwin32, 'file.lua'

    assert_equal ["duplicate file 'file.lua' on win32"], sc1.conflicts

    sc2 = ReaPack::Index::SourceCollection.new
    sc2['test'].push :all, 'file.lua'
    sc2['test'].push :darwin32, 'file.lua' # darwin32 first
    sc2['test'].push :win32, 'file.lua'

    assert_equal sc1.conflicts, sc2.conflicts
  end

  def test_remove_by_key
    sc = ReaPack::Index::SourceCollection.new
    sc['test'].push :all, 'file'

    sc['test'].clear
    sc['test'].push :all, 'file'

    assert_equal nil, sc.conflicts('test')
  end

  def test_dup
    sc1 = ReaPack::Index::SourceCollection.new
    sc1['test'].push :all, 'file'
    sc2 = sc1.dup

    sc1['test'].push :all, 'file'
    assert_nil sc2.conflicts

    sc2['test'].push :all, 'file'
    refute_nil sc2.conflicts
  end
end

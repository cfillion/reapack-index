class TestConflictDetector < MiniTest::Test
  include XMLHelper

  def test_unique
    cd = ReaPack::Index::ConflictDetector.new
    cd['grp', 'pkg'].push :all, 'file1.lua'
    cd['grp', 'pkg'].push :all, 'file2.lua'

    assert_nil cd.resolve('grp', 'pkg')
    assert_nil cd.resolve('grp')
  end

  def test_duplicates
    cd = ReaPack::Index::ConflictDetector.new
    cd['grp', 'pkg'].push :all, 'file1.lua'
    cd['grp', 'pkg'].push :all, 'file1.lua'
    cd['grp', 'pkg'].push :all, 'file2.lua'
    cd['grp', 'pkg'].push :all, 'file2.lua'

    assert_equal ["duplicate file 'file1.lua'", "duplicate file 'file2.lua'"],
      cd.resolve('grp', 'pkg')
  end

  def test_same_platform
    cd = ReaPack::Index::ConflictDetector.new
    cd['grp', 'test'].push :windows, 'file.lua'
    cd['grp', 'test'].push :windows, 'file.lua'

    assert_equal ["duplicate file 'file.lua' on windows"], cd.resolve('grp')
    assert_nil cd.resolve('other bucket')
  end

  def test_unmatching_platform
    cd = ReaPack::Index::ConflictDetector.new
    cd['grp', 'test'].push :darwin, 'file.lua'
    cd['grp', 'test'].push :windows, 'file.lua'

    assert_nil cd.resolve('grp')
  end

  def test_subplatform
    cd = ReaPack::Index::ConflictDetector.new
    cd['grp', 'test'].push :all, 'file.lua'
    cd['grp', 'test'].push :windows, 'file.lua'

    assert_equal ["duplicate file 'file.lua' on windows"], cd.resolve('grp')
  end

  def test_subsubplatform
    cd = ReaPack::Index::ConflictDetector.new
    cd['grp', 'test'].push :all, 'file.lua'
    cd['grp', 'test'].push :win32, 'file.lua'

    assert_equal ["duplicate file 'file.lua' on win32"], cd.resolve('grp')
  end

  def test_conflicts
    cd = ReaPack::Index::ConflictDetector.new
    cd['grp', 'package1.lua'].push :all, 'file1.lua'

    cd['grp', 'package2.lua'].push :all, 'file1.lua'
    cd['grp', 'package2.lua'].push :all, 'file2.lua'

    cd['grp', 'package3.lua'].push :windows, 'file2.lua'

    cd['grp', 'package4.lua'].push :darwin, 'file1.lua'

    assert_nil cd.resolve('grp', 'not_specified.lua'), 'id = not_specified'

    assert_equal ["'file1.lua' conflicts with 'package2.lua'"],
      cd.resolve('grp', 'package1.lua'), 'id = package1'

    assert_equal ["'file1.lua' conflicts with 'package1.lua'",
                  "'file2.lua' conflicts with 'package3.lua' on windows"],
      cd.resolve('grp', 'package2.lua'), 'id = package2'

    assert_equal ["'file2.lua' conflicts with 'package2.lua'"],
      cd.resolve('grp', 'package3.lua'), 'id = package3'

    # this conflict might happen on every platform,
    # so it should not be reported it as darwin-only
    assert_equal ["'file1.lua' conflicts with 'package1.lua'"],
      cd.resolve('grp', 'package4.lua'), 'id = package4'
  end

  def test_conflicts_bidirectional
    cd1 = ReaPack::Index::ConflictDetector.new

    a1 = cd1['grp', 'a']
    a1.push :all, 'file.lua'

    b1 = cd1['grp', 'b']
    b1.push :windows, 'file.lua'

    assert_equal ["'file.lua' conflicts with 'b' on windows"],
      a1.resolve, 'id = a'
    assert_equal ["'file.lua' conflicts with 'a'"],
      b1.resolve, 'id = b'

    cd2 = ReaPack::Index::ConflictDetector.new
    a2 = cd1['grp', 'a']
    a2.push :windows, 'file.lua'

    b2 = cd1['grp', 'b']
    b2.push :all, 'file.lua'

    assert_equal a1.resolve, a2.resolve
    assert_equal b1.resolve, b2.resolve
  end

  def test_platform_selection
    cd1 = ReaPack::Index::ConflictDetector.new
    cd1['grp1', 'a'].push :all, 'file.lua'
    cd1['grp1', 'b'].push :windows, 'file.lua'
    cd1['grp1', 'c'].push :win32, 'file.lua'

    assert_equal ["'file.lua' conflicts with 'b' on windows"],
      cd1.resolve('grp1', 'a'), 'id = a (grp1)'

    cd1['grp2', 'a'].push :all, 'file.lua'
    cd1['grp2', 'b'].push :darwin, 'file.lua'
    cd1['grp2', 'c'].push :win32, 'file.lua'

    assert_equal ["'file.lua' conflicts with 'b' on darwin"],
      cd1.resolve('grp2', 'a'), 'id = a (grp2)'
  end

  def test_duplicate_platform_selection
    cd = ReaPack::Index::ConflictDetector.new
    cd['grp', 'test'].push :windows, 'file.lua'
    cd['grp', 'test'].push :all, 'file.lua'
    assert_equal ["duplicate file 'file.lua' on windows"], cd.resolve('grp')

    cd['grp', 'test'].push :all, 'file.lua'
    assert_equal ["duplicate file 'file.lua'"], cd.resolve('grp')
  end

  def test_platform_same_level
    cd1 = ReaPack::Index::ConflictDetector.new
    cd1['grp', 'test'].push :all, 'file.lua'
    cd1['grp', 'test'].push :win32, 'file.lua' # win32 first
    cd1['grp', 'test'].push :darwin32, 'file.lua'

    assert_equal ["duplicate file 'file.lua' on win32"], cd1.resolve('grp')

    cd2 = ReaPack::Index::ConflictDetector.new
    cd2['grp', 'test'].push :all, 'file.lua'
    cd2['grp', 'test'].push :darwin32, 'file.lua' # darwin32 first
    cd2['grp', 'test'].push :win32, 'file.lua'

    assert_equal cd1.resolve('grp'), cd2.resolve('grp')
  end

  def test_remove_by_key
    cd = ReaPack::Index::ConflictDetector.new
    cd['grp', 'test'].push :all, 'file'

    cd['grp', 'test'].clear
    cd['grp', 'test'].push :all, 'file'

    assert_equal nil, cd.resolve('grp', 'test')
  end

  def test_clone
    cd1 = ReaPack::Index::ConflictDetector.new
    cd1['grp', 'test'].push :all, 'file'

    cd2 = cd1.clone

    cd1['grp', 'test'].push :all, 'file'
    assert_nil cd2.resolve('grp')

    cd2['grp', 'test'].push :all, 'file'
    refute_nil cd2.resolve('grp')
  end

  def test_clear
    cd = ReaPack::Index::ConflictDetector.new
    cd['grp', 'test'].push :all, 'file'

    cd.clear
    cd['grp', 'test'].push :all, 'file'

    assert_equal nil, cd.resolve('grp', 'test')
  end

  def test_load_xml
    xml = <<-XML
<index version="1">
  <category name="Other">
    <reapack name="test1.lua" type="script">
      <version name="1.0">
        <source platform="all">http://irrelevant/url</source>
        <source platform="all" file="background.png">http://google.com</source>
        <source platform="win32" file="background.png">http://duplicate/file/</source>
      </version>
    </reapack>
    <reapack name="test2.lua" type="script">
      <version name="1.0">
        <source platform="all" file="test1.lua">http://oops/conflict/</source>
      </version>
    </reapack>
    <reapack name="empty_ver.lua" type="script">
      <version name="a"/>
    </reapack>
    <reapack name="empty_pkg.lua"/>
  </category>
  <category name="Scripts">
    <reapack name="test3.lua" type="script">
      <version name="1.0">
        <source platform="all" file="../Other/test1.lua">http://cross/category</source>
      </version>
    </reapack>
    <reapack name="no_platform.lua" type="script">
      <version name="1.0">
        <source file="picture">http://cross/category</source>
      </version>
    </reapack>
    <reapack name="no_platform.lua" type="script">
      <version name="1.0">
        <source platform="bacon" file="picture">http://cross/category</source>
      </version>
    </reapack>
  </category>
</index>
    XML

    cd = ReaPack::Index::ConflictDetector.new
    cd.load_xml make_node(xml)

    assert_equal ["'Other/test1.lua' conflicts with 'Other/test2.lua'",
                  "duplicate file 'Other/background.png' on win32"],
      cd.resolve(:script, 'Other/test1.lua'), 'test1'

    assert_equal ["'Other/test1.lua' conflicts with 'Other/test1.lua'"],
      cd.resolve(:script, 'Other/test2.lua'), 'test2'

    assert_equal ["'Other/test1.lua' conflicts with 'Other/test1.lua'"],
      cd.resolve(:script, 'Scripts/test3.lua'), 'test3'

    cd.resolve :script, 'Scripts/no_platform.lua'
    cd.resolve :script, 'Scripts/weird_platform.lua'
  end
end

class TestConflictDetector < MiniTest::Test
  include XMLHelper

  def test_unique
    cd = ReaPack::Index::ConflictDetector.new
    cd['pkg'].push :grp, :all, 'file1.lua'
    cd['pkg'].push :grp, :all, 'file2.lua'

    assert_nil cd['pkg'].resolve
    assert_nil cd.resolve(:grp, 'pkg')
    assert_nil cd.resolve(:grp)
  end

  def test_duplicates
    cd = ReaPack::Index::ConflictDetector.new
    cd['pkg'].push :grp, :all, 'file1.lua'
    cd['pkg'].push :grp, :all, 'file1.lua'
    cd['pkg'].push :grp, :all, 'file2.lua'
    cd['pkg'].push :grp, :all, 'file2.lua'

    expected = ["duplicate file 'file1.lua'", "duplicate file 'file2.lua'"]
    assert_equal expected, cd['pkg'].resolve
    assert_equal expected, cd.resolve(:grp, 'pkg')
    assert_equal expected, cd.resolve(:grp)
  end

  def test_same_platform
    cd = ReaPack::Index::ConflictDetector.new
    cd['test'].push :grp, :windows, 'file.lua'
    cd['test'].push :grp, :windows, 'file.lua'

    assert_equal ["duplicate file 'file.lua' on windows"], cd.resolve(:grp)
    assert_nil cd.resolve(:other_bucket)
  end

  def test_unmatching_platform
    cd = ReaPack::Index::ConflictDetector.new
    cd['test'].push :grp, :darwin, 'file.lua'
    cd['test'].push :grp, :windows, 'file.lua'

    assert_nil cd.resolve(:grp)
  end

  def test_subplatform
    cd = ReaPack::Index::ConflictDetector.new
    cd['test'].push :grp, :all, 'file.lua'
    cd['test'].push :grp, :windows, 'file.lua'

    assert_equal ["duplicate file 'file.lua' on windows"], cd.resolve(:grp)
  end

  def test_subsubplatform
    cd = ReaPack::Index::ConflictDetector.new
    cd['test'].push :grp, :all, 'file.lua'
    cd['test'].push :grp, :win32, 'file.lua'

    assert_equal ["duplicate file 'file.lua' on win32"], cd.resolve(:grp)
  end

  def test_conflicts
    cd = ReaPack::Index::ConflictDetector.new
    cd['package1.lua'].push :grp, :all, 'file1.lua'

    cd['package2.lua'].push :grp, :all, 'file1.lua'
    cd['package2.lua'].push :grp, :all, 'file2.lua'

    cd['package3.lua'].push :grp, :windows, 'file2.lua'

    cd['package4.lua'].push :grp, :darwin, 'file1.lua'

    assert_nil cd.resolve(:grp, 'not_specified.lua'), 'id = not_specified'

    assert_equal ["'file1.lua' conflicts with 'package2.lua'"],
      cd.resolve(:grp, 'package1.lua'), 'id = package1'
    assert_equal cd.resolve(:grp, 'package1.lua'), cd['package1.lua'].resolve

    assert_equal ["'file1.lua' conflicts with 'package1.lua'",
                  "'file2.lua' conflicts with 'package3.lua' on windows"],
      cd.resolve(:grp, 'package2.lua'), 'id = package2'

    assert_equal ["'file2.lua' conflicts with 'package2.lua'"],
      cd.resolve(:grp, 'package3.lua'), 'id = package3'

    # this conflict might happen on every platform,
    # so it should not be reported it as darwin-only
    assert_equal ["'file1.lua' conflicts with 'package1.lua'"],
      cd.resolve(:grp, 'package4.lua'), 'id = package4'
  end

  def test_conflicts_bidirectional
    cd1 = ReaPack::Index::ConflictDetector.new

    a1 = cd1['a']
    a1.push :grp, :all, 'file.lua'

    b1 = cd1['b']
    b1.push :grp, :windows, 'file.lua'

    assert_equal ["'file.lua' conflicts with 'b' on windows"],
      a1.resolve, 'id = a'
    assert_equal ["'file.lua' conflicts with 'a'"],
      b1.resolve, 'id = b'

    cd2 = ReaPack::Index::ConflictDetector.new
    a2 = cd1['a']
    a2.push :grp, :windows, 'file.lua'

    b2 = cd1['b']
    b2.push :grp, :all, 'file.lua'

    assert_equal a1.resolve, a2.resolve
    assert_equal b1.resolve, b2.resolve
  end

  def test_platform_selection
    cd1 = ReaPack::Index::ConflictDetector.new
    cd1['a'].push :grp1, :all, 'file.lua'
    cd1['b'].push :grp1, :windows, 'file.lua'
    cd1['c'].push :grp1, :win32, 'file.lua'

    assert_equal ["'file.lua' conflicts with 'b' on windows"],
      cd1.resolve(:grp1, 'a'), 'id = a (grp1)'

    cd1['a'].push :grp2, :all, 'file.lua'
    cd1['b'].push :grp2, :darwin, 'file.lua'
    cd1['c'].push :grp2, :win32, 'file.lua'

    assert_equal ["'file.lua' conflicts with 'b' on darwin"],
      cd1.resolve(:grp2, 'a'), 'id = a (grp2)'
  end

  def test_duplicate_platform_selection
    cd = ReaPack::Index::ConflictDetector.new
    cd['test'].push :grp, :windows, 'file.lua'
    cd['test'].push :grp, :all, 'file.lua'
    assert_equal ["duplicate file 'file.lua' on windows"], cd.resolve(:grp)

    cd['test'].push :grp, :all, 'file.lua'
    assert_equal ["duplicate file 'file.lua'"], cd.resolve(:grp)
  end

  def test_platform_same_level
    cd1 = ReaPack::Index::ConflictDetector.new
    cd1['test'].push :grp, :all, 'file.lua'
    cd1['test'].push :grp, :win32, 'file.lua' # win32 first
    cd1['test'].push :grp, :darwin32, 'file.lua'

    assert_equal ["duplicate file 'file.lua' on win32"], cd1.resolve(:grp)

    cd2 = ReaPack::Index::ConflictDetector.new
    cd2['test'].push :grp, :all, 'file.lua'
    cd2['test'].push :grp, :darwin32, 'file.lua' # darwin32 first
    cd2['test'].push :grp, :win32, 'file.lua'

    assert_equal cd1.resolve(:grp), cd2.resolve(:grp)
  end

  def test_remove_by_key
    cd = ReaPack::Index::ConflictDetector.new
    cd['test'].push :grp, :all, 'file'

    cd['test'].clear
    cd['test'].push :grp, :all, 'file'

     assert_nil cd.resolve(:grp, 'test')
  end

  def test_clone
    cd1 = ReaPack::Index::ConflictDetector.new
    cd1['test'].push :grp, :all, 'file'

    cd2 = cd1.clone

    cd1['test'].push :grp, :all, 'file'
    assert_nil cd2.resolve(:grp)

    cd2['test'].push :grp, :all, 'file'
    refute_nil cd2.resolve(:grp)
  end

  def test_clear
    cd = ReaPack::Index::ConflictDetector.new
    cd['test'].push :grp, :all, 'file'

    cd.clear
    cd['test'].push :grp, :all, 'file'

    assert_nil cd.resolve(:grp, 'test')
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
    <reapack name="weird_platform.lua" type="script">
      <version name="1.0">
        <source platform="bacon" file="picture">http://cross/category</source>
      </version>
    </reapack>
    <reapack name="explicit_type.lua" type="script">
      <version name="1.0">
        <source type="effect" file="picture">http://cross/category</source>
      </version>
    </reapack>
  </category>
</index>
    XML

    cd = ReaPack::Index::ConflictDetector.new
    cd.load_xml make_node(xml)

    assert_equal ["'Other/test1.lua' conflicts with 'Other/test2.lua'",
                  "duplicate file 'Other/background.png' on win32"],
      cd['Other/test1.lua'].resolve, 'test1'

    assert_equal ["'Other/test1.lua' conflicts with 'Other/test1.lua'"],
      cd['Other/test2.lua'].resolve, 'test2'

    assert_equal ["'Other/test1.lua' conflicts with 'Other/test1.lua'"],
      cd['Scripts/test3.lua'].resolve, 'test3'

    cd['Scripts/no_platform.lua'].resolve
    cd['Scripts/weird_platform.lua'].resolve

    assert_nil cd['Scripts/explicit_type.lua'].resolve
  end

  def test_unknown_platform
    cd = ReaPack::Index::ConflictDetector.new
    cd['test1'].push :grp, :unknown, 'file'
    cd['test2'].push :grp, :all, 'file'

    assert_equal ["'file' conflicts with 'test2'"], cd['test1'].resolve
  end
end

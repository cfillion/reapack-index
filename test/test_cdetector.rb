class TestConflictDetector < MiniTest::Test
  def test_unique
    cd = ReaPack::Index::ConflictDetector.new
    cd['pkg'].push :all, 'file1.lua'
    cd['pkg'].push :all, 'file2.lua'

    assert_nil cd.conflicts('pkg')
    assert_nil cd.conflicts
  end

  def test_duplicates
    cd = ReaPack::Index::ConflictDetector.new
    cd['pkg'].push :all, 'file1.lua'
    cd['pkg'].push :all, 'file1.lua'
    cd['pkg'].push :all, 'file2.lua'
    cd['pkg'].push :all, 'file2.lua'

    assert_equal ["duplicate file 'file1.lua'", "duplicate file 'file2.lua'"],
      cd.conflicts('pkg')
  end

  def test_same_platform
    cd = ReaPack::Index::ConflictDetector.new
    cd['test'].push :windows, 'file.lua'
    cd['test'].push :windows, 'file.lua'

    assert_equal ["duplicate file 'file.lua' on windows"], cd.conflicts
  end

  def test_unmatching_platform
    cd = ReaPack::Index::ConflictDetector.new
    cd['test'].push :darwin, 'file.lua'
    cd['test'].push :windows, 'file.lua'

    assert_nil cd.conflicts
  end

  def test_subplatform
    cd = ReaPack::Index::ConflictDetector.new
    cd['test'].push :all, 'file.lua'
    cd['test'].push :windows, 'file.lua'

    assert_equal ["duplicate file 'file.lua' on windows"], cd.conflicts
  end

  def test_subsubplatform
    cd = ReaPack::Index::ConflictDetector.new
    cd['test'].push :all, 'file.lua'
    cd['test'].push :win32, 'file.lua'

    assert_equal ["duplicate file 'file.lua' on win32"], cd.conflicts
  end

  def test_conflicts
    cd = ReaPack::Index::ConflictDetector.new
    cd['package1.lua'].push :all, 'file1.lua'

    cd['package2.lua'].push :all, 'file1.lua'
    cd['package2.lua'].push :all, 'file2.lua'

    cd['package3.lua'].push :windows, 'file2.lua'

    cd['package4.lua'].push :darwin, 'file1.lua'

    assert_nil cd.conflicts('not_specified.lua'), 'id = not_specified'

    assert_equal ["'file1.lua' conflicts with 'package2.lua'"],
      cd.conflicts('package1.lua'), 'id = package1'

    assert_equal ["'file1.lua' conflicts with 'package1.lua'",
                  "'file2.lua' conflicts with 'package3.lua' on windows"],
      cd.conflicts('package2.lua'), 'id = package2'

    assert_equal ["'file2.lua' conflicts with 'package2.lua'"],
      cd.conflicts('package3.lua'), 'id = package3'

    # this conflict might happen on every platform,
    # so it should not be reported it as darwin-only
    assert_equal ["'file1.lua' conflicts with 'package1.lua'"],
      cd.conflicts('package4.lua'), 'id = package4'
  end

  def test_conflicts_bidirectional
    cd1 = ReaPack::Index::ConflictDetector.new
    cd1['a'].push :all, 'file.lua'
    cd1['b'].push :windows, 'file.lua'

    assert_equal ["'file.lua' conflicts with 'b' on windows"],
      cd1.conflicts('a'), 'id = a'
    assert_equal ["'file.lua' conflicts with 'a'"], cd1.conflicts('b'), 'id = b'

    cd2 = ReaPack::Index::ConflictDetector.new
    cd2['b'].push :windows, 'file.lua'
    cd2['a'].push :all, 'file.lua'

    assert_equal cd1.conflicts('a'), cd2.conflicts('a')
    assert_equal cd1.conflicts('b'), cd2.conflicts('b')
  end

  def test_conflicts_platform_selection
    cd1 = ReaPack::Index::ConflictDetector.new
    cd1['a'].push :all, 'file.lua'
    cd1['b'].push :windows, 'file.lua'
    cd1['c'].push :win32, 'file.lua'

    assert_equal ["'file.lua' conflicts with 'b' on windows"],
      cd1.conflicts('a'), 'id = a'
  end

  def test_duplicate_platform_selection
    cd = ReaPack::Index::ConflictDetector.new
    cd['test'].push :windows, 'file.lua'
    cd['test'].push :all, 'file.lua'
    assert_equal ["duplicate file 'file.lua' on windows"], cd.conflicts

    cd['test'].push :all, 'file.lua'
    assert_equal ["duplicate file 'file.lua'"], cd.conflicts
  end

  def test_platform_same_level
    cd1 = ReaPack::Index::ConflictDetector.new
    cd1['test'].push :all, 'file.lua'
    cd1['test'].push :win32, 'file.lua' # win32 first
    cd1['test'].push :darwin32, 'file.lua'

    assert_equal ["duplicate file 'file.lua' on win32"], cd1.conflicts

    cd2 = ReaPack::Index::ConflictDetector.new
    cd2['test'].push :all, 'file.lua'
    cd2['test'].push :darwin32, 'file.lua' # darwin32 first
    cd2['test'].push :win32, 'file.lua'

    assert_equal cd1.conflicts, cd2.conflicts
  end

  def test_remove_by_key
    cd = ReaPack::Index::ConflictDetector.new
    cd['test'].push :all, 'file'

    cd['test'].clear
    cd['test'].push :all, 'file'

    assert_equal nil, cd.conflicts('test')
  end

  def test_dup
    cd1 = ReaPack::Index::ConflictDetector.new
    cd1['test'].push :all, 'file'
    cd2 = cd1.dup

    cd1['test'].push :all, 'file'
    assert_nil cd2.conflicts

    cd2['test'].push :all, 'file'
    refute_nil cd2.conflicts
  end
end

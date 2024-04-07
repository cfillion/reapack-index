require File.expand_path '../helper', __FILE__

class TestPackage < Minitest::Test
  include XMLHelper

  def test_change_type
    before = make_node '<reapack name="pkg"/>'
    after = '<reapack name="pkg" type="script"/>'

    pkg = ReaPack::Index::Package.new before
    assert_nil pkg.type

    pkg.type = 'script'
    assert pkg.modified?, 'package is not modified'
    assert_equal :script, pkg.type

    assert_equal after, before.to_s
  end

  def test_set_same_type
    before = make_node '<reapack name="pkg" type="script"/>'

    pkg = ReaPack::Index::Package.new before

    assert_equal :script, pkg.type
    pkg.type = pkg.type

    refute pkg.modified?, 'package is modified'
  end

  def test_set_description
    before = make_node '<reapack name="pkg"/>'
    after = '<reapack name="pkg" desc="hello world"/>'

    pkg = ReaPack::Index::Package.new before
    assert_empty pkg.description

    pkg.description = 'hello world'
    assert pkg.modified?, 'package is not modified'
    assert_equal 'hello world', pkg.description

    assert_equal after, before.to_s
  end

  def test_set_same_description
    before = make_node '<reapack name="pkg" desc="hello world"/>'

    pkg = ReaPack::Index::Package.new before

    assert_equal 'hello world', pkg.description
    pkg.description = pkg.description

    refute pkg.modified?, 'package is modified'
  end

  def test_remove_description
    before = make_node '<reapack name="pkg" desc="hello world"/>'
    after = '<reapack name="pkg"/>'

    pkg = ReaPack::Index::Package.new before
    assert_equal 'hello world', pkg.description

    pkg.description = nil
    assert pkg.modified?, 'package is not modified'

    assert_equal after, before.to_s
  end

  def test_set_metadata
    before = make_node '<reapack name="pkg"/>'

    pkg = ReaPack::Index::Package.new before
    refute pkg.modified?, 'package is modified'

    pkg.metadata.about = 'hello world'
    assert pkg.modified?, 'package is not modified'

    assert_match /<metadata>.+<description>/m, before.to_s
  end

  def test_versions
    before = make_node <<-XML
    <reapack name="pkg" type="script">
      <version name="1.0" />
    </reapack>
    XML

    pkg = ReaPack::Index::Package.new before
    assert pkg.has_version?('1.0'), 'version 1.0 not found'
    refute pkg.has_version?('1.1'), 'version 1.1 was found?!'

    versions = pkg.versions
    assert_equal 1, versions.size
    assert_kind_of ReaPack::Index::Version, versions.first
    assert_equal '1.0', versions.first.name
  end

  def test_new_version
    before = make_node <<-XML
    <reapack name="pkg" type="script">
      <version name="1.0" />
    </reapack>
    XML

    pkg = ReaPack::Index::Package.new before

    pkg.version '1.0'
    refute pkg.modified?, 'package is modified'

    ver11 = pkg.version '1.1'
    assert pkg.modified?, 'package not modified'

    block_result = []
    pkg.version '1.1' do |*vars|
      block_result << vars
    end

    assert_equal [[ver11]], block_result

    assert pkg.has_version?('1.1'), 'version 1.1 not found'
  end

  def test_new_version_similar
    before = make_node '<reapack name="pkg" type="script"/>'

    pkg = ReaPack::Index::Package.new before
    pkg.version '1.01'

    error = assert_raises ReaPack::Index::Error do
      pkg.version '1.1'
    end
    assert_equal 'version 1.1 is a duplicate of version 1.01', error.message

    error = assert_raises ReaPack::Index::Error do
      pkg.version '1//1'
    end
    assert_equal 'version 1//1 is a duplicate of version 1.01', error.message

    pkg.version '1.0.1' # should not be mistaken for 1.1
    error = assert_raises ReaPack::Index::Error do
      pkg.version '1.000.1'
    end
    assert_equal 'version 1.000.1 is a duplicate of version 1.0.1', error.message

    pkg.version '01pre1'
    error = assert_raises ReaPack::Index::Error do
      pkg.version '1.pre01'
    end
    assert_equal 'version 1.pre01 is a duplicate of version 01pre1', error.message

    pkg.version '1PRE1' # not the same as 01pre1
  end

  def test_category_and_path
    pkg1 = ReaPack::Index::Package.new make_node('<reapack/>')
    assert_nil pkg1.category
    assert_nil pkg1.path
    assert_nil pkg1.topdir

    pkg2 = ReaPack::Index::Package.create 'test',
      make_node('<category name="Hello/World"/>')

    assert_equal 'Hello/World', pkg2.category
    assert_equal 'Hello/World/test', pkg2.path
    assert_equal 'Hello', pkg2.topdir
  end
end

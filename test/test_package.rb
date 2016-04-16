require File.expand_path '../helper', __FILE__

class TestPackage < MiniTest::Test
  include XMLHelper

  def test_change_type
    before = make_node '<reapack name="1.0"/>'
    after = '<reapack name="1.0" type="script"/>'

    pkg = ReaPack::Index::Package.new before
    assert_nil pkg.type

    pkg.type = 'script'
    assert pkg.modified?, 'package is not modified'
    assert_equal :script, pkg.type

    assert_equal after, before.to_s
  end

  def test_set_same_type
    before = make_node '<reapack name="1.0" type="script"/>'

    pkg = ReaPack::Index::Package.new before

    assert_equal :script, pkg.type
    pkg.type = pkg.type

    refute pkg.modified?, 'package is modified'
  end

  def test_versions
    before = make_node <<-XML
    <reapack name="1.0" type="script">
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

  def test_get_or_create_version
    before = make_node <<-XML
    <reapack name="1.0" type="script">
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

  def test_category_and_path
    pkg1 = ReaPack::Index::Package.new make_node('<reapack/>')
    assert_nil pkg1.category
    assert_nil pkg1.path

    pkg2 = ReaPack::Index::Package.create 'test',
      make_node('<category name="Hello/World"/>')

    assert_equal 'Hello/World', pkg2.category
    assert_equal 'Hello/World/test', pkg2.path
  end
end

require File.expand_path '../../helper', __FILE__

TestCLI ||= Class.new MiniTest::Test

class TestCLI::Metadata < MiniTest::Test
  include CLIHelper

  def test_website_link
    wrapper ['-l http://cfillion.tk'] do
      assert_output "1 new website link, empty index\n" do
        assert_equal true, @cli.run
      end

      assert_match 'rel="website">http://cfillion.tk</link>', read_index
    end
  end

  def test_donation_link
    wrapper ['--donation-link', 'Link Label=http://cfillion.tk'] do
      assert_output "1 new donation link, empty index\n" do
        assert_equal true, @cli.run
      end

      assert_match 'rel="donation" href="http://cfillion.tk">Link Label</link>',
        read_index
    end
  end

  def test_invalid_link
    wrapper ['--link', 'shinsekai yori', '--donation-link', 'hello world',
             '--link', 'http://cfillion.tk'] do
      stdout, stderr = capture_io do
        assert_equal true, @cli.run
      end

      assert_equal "1 new website link, empty index\n", stdout
      assert_match /warning: --link: invalid link 'shinsekai yori'/i, stderr
      assert_match /warning: --donation-link: invalid link 'hello world'/i, stderr
      assert_match 'rel="website">http://cfillion.tk</link>', read_index
    end
  end

  def test_remove_link
    wrapper ['--link', 'http://test.com', '--link', '-http://test.com'] do
      assert_output "1 new website link, 1 removed website link, empty index\n" do
        assert_equal true, @cli.run
      end

      refute_match 'rel="website">http://test.com</link>', read_index
    end
  end

  def test_list_links
    setup = proc {
      mkfile 'index.xml', <<-XML
<?xml version="1.0" encoding="utf-8"?>
<index version="1">
  <metadata>
    <link rel="website" href="http://anidb.net/a9002">Shinsekai Yori</link>
    <link rel="donation" href="http://paypal.com">Donate!</link>
    <link rel="website">http://cfillion.tk</link>
      XML
    }

    wrapper ['--ls-links'], setup: setup do
      stdin, stderr = capture_io do
        assert_equal true, @cli.run
      end

      expected = <<-OUT
[website] Shinsekai Yori (http://anidb.net/a9002)
[website] http://cfillion.tk
[donation] Donate! (http://paypal.com)
      OUT

      assert_equal expected, stdin
      assert_empty stderr
    end
  end

  def test_about
    opts = ['--about']
    setup = proc { opts << mkfile('README.md', '# Hello World') }

    wrapper opts, setup: setup do
      assert_output "1 modified metadata, empty index\n" do
        assert_equal true, @cli.run
      end

      assert_match 'Hello World', read_index
    end
  end

  def test_about_file_not_found
    # 404.md is read in the working directory
    wrapper ['--about=404.md'] do
      assert_output "empty index\n",
          /warning: --about: no such file or directory - 404.md/i do
        assert_equal true, @cli.run
      end
    end
  end

  def test_about_pandoc_not_found
    old_path = ENV['PATH']

    opts = ['--about']

    setup = proc {
      opts << mkfile('README.md', '# Hello World')
    }

    wrapper opts, setup: setup do
      assert_output "empty index\n", /pandoc executable cannot be found/i do
        ENV['PATH'] = String.new
        assert_equal true, @cli.run
      end
    end
  ensure
    ENV['PATH'] = old_path
  end

  def test_about_clear
    setup = proc {
      mkfile 'index.xml', <<-XML
<index>
  <metadata>
    <description><![CDATA[Hello World]]></description>
  </metadata>
</index>
      XML
    }

    wrapper ['--remove-about'], setup: setup do
      assert_output "1 modified metadata\n" do
        assert_equal true, @cli.run
      end

      refute_match 'Hello World', read_index
    end
  end

  def test_about_dump
    setup = proc {
      mkfile 'index.xml', <<-XML
<index>
  <metadata>
    <description><![CDATA[Hello World]]></description>
  </metadata>
</index>
      XML
    }

    wrapper ['--dump-about'], setup: setup do
      assert_output 'Hello World' do
        assert_equal true, @cli.run
      end
    end
  end

  def test_unset_name_warning
    wrapper do
      _, stderr = capture_io do
        assert_equal true, @cli.run
      end

      assert_match /index is unnamed/i, stderr
      refute_match File.dirname($0), stderr
      refute_match 'name', read_index
    end
  end

  def test_set_name
    wrapper ['--name=Hello World'] do
      _, stderr = capture_io do
        assert_equal true, @cli.run
      end

      refute_match /index is unnamed/i, stderr
      assert_match 'name="Hello World"', read_index
    end
  end

  def test_set_name_invalid
    wrapper ['--name=Hello/World'] do
      _, stderr = capture_io do
        assert_equal true, @cli.run
      end

      refute_match /The name of this index is unset/i, stderr
      assert_match /invalid name 'Hello\/World'/i, stderr
    end
  end
end

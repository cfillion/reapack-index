require 'coveralls'
require 'simplecov'

Coveralls::Output.silent = true

SimpleCov.formatters = [
  SimpleCov::Formatter::HTMLFormatter,
  Coveralls::SimpleCov::Formatter,
]

SimpleCov.start {
  project_name 'reapack-index'
  add_filter '/test/'
}

require 'reapack/index'
require 'minitest/autorun'

String.disable_colorization = true

module XMLHelper
  def make_node(markup)
    Nokogiri::XML(markup, &:noblanks).root
  end
end

module IndexHelper
  def setup
    @real_path = File.expand_path '../data/index.xml', __FILE__
    @dummy_path = Dir::Tmpname.create('index.xml') {|path| path }

    @commit = '399f5609cff3e6fd92b5542d444fbf86da0443c6'
  end

  def teardown
    File.delete @dummy_path if File.exist? @dummy_path
  end
end

module GitHelper
  def init_git
    path = Dir.mktmpdir 'test-repository'
    repo = Rugged::Repository.init_at path
    repo.config['user.name'] = 'John Doe'
    repo.config['user.email'] = 'john@doe.com'
    repo.config['commit.gpgsign'] = false

    @git = ReaPack::Index::Git.new path
    [path, repo]
  end

  def mkfile(file, content = String.new)
    fn = File.join @git.path, file
    FileUtils.mkdir_p File.dirname(fn)
    File.write fn, content
    fn
  end
end

module CLIHelper
  include GitHelper

  INVALID_HASHES = [
    'hello world', '0000000000000000000000000000000000000000',
    '0000000000000000000000000000000000000deadbeef',
  ].freeze

  class FakeIO
    def initialize
      @getch = 'n'
    end

    attr_accessor :getch
  end

  def fake_input
    stdin = $stdin
    $stdin = FakeIO.new

    yield $stdin
  ensure
    $stdin = stdin
  end

  def wrapper(args = [], options = {})
    old_pwd = Dir.pwd

    path, repo = init_git

    if options[:remote] != false
      options[:remote] ||= 'git@github.com:cfillion/test-repository.git'
      repo.remotes.create 'origin', options[:remote]
    end

    options[:setup].call if options.has_key? :setup

    @indexer = ReaPack::Index::CLI.new \
      ['--no-progress', '--no-commit'] + args + ['--', path]

    yield if block_given?
  ensure
    @git = @indexer = nil
    Dir.chdir old_pwd
    FileUtils.rm_r path
  end

  def read_index(file = 'index.xml')
    File.read File.expand_path(file, @git.path)
  end
end

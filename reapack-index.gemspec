# coding: utf-8
lib = File.expand_path '../lib', __FILE__
$LOAD_PATH.unshift lib unless $LOAD_PATH.include? lib

require 'reapack/index/gem_version'

Gem::Specification.new do |spec|
  spec.name          = 'reapack-index'
  spec.version       = ReaPack::Index::VERSION
  spec.authors       = ['cfillion']
  spec.email         = ['reapack-index@cfillion.ca']
  spec.summary       = 'Package indexer for git-based ReaPack repositories'
  spec.homepage      = 'https://github.com/cfillion/reapack-index'
  spec.license       = 'GPL-3.0+'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 2.3'

  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'coveralls', '~> 0.8'
  spec.add_development_dependency 'minitest', '~> 5.8'
  spec.add_development_dependency 'rake', '~> 12.0'
  spec.add_development_dependency 'simplecov', '~> 0.11'

  spec.add_runtime_dependency 'addressable', '~> 2.4'
  spec.add_runtime_dependency 'colorize', '~> 0.7'
  spec.add_runtime_dependency 'gitable', '~> 0.3'
  spec.add_runtime_dependency 'metaheader', '~> 2.0'
  spec.add_runtime_dependency 'nokogiri', '~> 1.7'
  spec.add_runtime_dependency 'pandoc-ruby', '~> 2.0'
  spec.add_runtime_dependency 'rugged', '~> 0.25', '< 0.28'
  spec.add_runtime_dependency 'stable_sort', '~> 1.1'
end

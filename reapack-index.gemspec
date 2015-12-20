# coding: utf-8
lib = File.expand_path '../lib', __FILE__
$LOAD_PATH.unshift lib unless $LOAD_PATH.include? lib

require 'reapack/index/gem_version'

Gem::Specification.new do |spec|
  spec.name          = "reapack-index"
  spec.version       = ReaPack::Index::VERSION
  spec.authors       = ["cfillion"]
  spec.email         = ["reapack-index@cfillion.tk"]
  spec.summary       = %q{Package indexer for ReaPack-based repositories}
  spec.homepage      = "https://github.com/cfillion/reapack-indexer"
  spec.license       = "LGPL-3.0+"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency 'bundler', '~> 1.10'
  spec.add_development_dependency 'coveralls', '~> 0.8'
  spec.add_development_dependency 'minitest', '~> 5.8'
  spec.add_development_dependency 'rake'

  spec.add_runtime_dependency 'git', '~> 1.2'
  spec.add_runtime_dependency 'metaheader', '~> 0.1'
  spec.add_runtime_dependency 'nokogiri', '~> 1.6'
end

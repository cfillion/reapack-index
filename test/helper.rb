if ENV['CI']
  require 'coveralls'

  Coveralls::Output.silent = true
  Coveralls.wear!
end

require 'reapack/indexer'
require 'minitest/autorun'

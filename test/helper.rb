if ENV['CI']
  require 'coveralls'

  Coveralls::Output.silent = true
  Coveralls.wear!
end

require 'reapack/index'
require 'minitest/autorun'

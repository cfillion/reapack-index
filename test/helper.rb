if ENV['CI']
  require 'coveralls'

  Coveralls::Output.silent = true
  Coveralls.wear!
else
  require 'simplecov'

  SimpleCov.start {
    project_name 'reapack-index'
    add_filter '/test/'
  }
end

require 'reapack/index'
require 'minitest/autorun'

module MiniTest
  class Test
    def make_node(markup)
      setup = proc {|config| config.noblanks }
      Nokogiri::XML(markup, &setup).root
    end
  end
end

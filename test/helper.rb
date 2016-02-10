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

module MiniTest
  class Test
    def make_node(markup)
      setup = proc {|config| config.noblanks }
      Nokogiri::XML(markup, &setup).root
    end
  end
end

String.disable_colorization = true

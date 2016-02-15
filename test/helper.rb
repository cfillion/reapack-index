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

module XMLHelper
  def make_node(markup)
    Nokogiri::XML(markup, &:noblanks).root
  end
end

String.disable_colorization = true

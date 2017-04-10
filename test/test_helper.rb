$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'shells'

require 'minitest/reporters'
MiniTest::Reporters.use!

require 'minitest/autorun'

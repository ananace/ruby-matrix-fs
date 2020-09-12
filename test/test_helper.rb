# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/test/'
  add_filter '/vendor/'
end

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'matrix_fs'

require 'test/unit'
require 'mocha/test_unit'

# frozen_string_literal: true

require 'simplecov'
# Coverage report in coverage/index.html. Started before the library is loaded. The command line tests run in new processes
# and are not counted.
SimpleCov.start do
  add_filter '/test/'
  enable_coverage :branch
  minimum_coverage line: 80
end

require 'json'
require 'minitest/autorun'
require 'tmpdir'
require 'open3'
require 'rbconfig'
require_relative '../lib/require_hygiene'

module TestHelper
  ROOT = File.expand_path('..', __dir__)
  DEFECTS = File.join(ROOT, 'test/fixtures/defects')
  EXE = File.join(ROOT, 'bin/require_hygiene')

  # Run the command line in a new process
  # @return [Array(String, String, Integer)] stdout, stderr, exit status
  def run_cli(*args)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, EXE, *args)
    [stdout, stderr, status.exitstatus]
  end
end

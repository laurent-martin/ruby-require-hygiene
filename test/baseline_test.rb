# frozen_string_literal: true

require_relative 'test_helper'

class BaselineTest < Minitest::Test
  include TestHelper

  def diagnostic(message, line = 1)
    RequireHygiene::Diagnostic.new(rule: 'unused_require', file: 'lib/a.rb', line: line, column: 1, confidence: 'medium', severity: 'info', message: message)
  end

  def test_known_findings_are_not_reported_whatever_the_line
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'todo.yml')
      RequireHygiene::Baseline.write(file, [diagnostic('old', 3)])
      fresh, known, fixed = RequireHygiene::Baseline.new(file).partition([diagnostic('old', 30), diagnostic('new')])
      assert_equal(['new'], fresh.map(&:message))
      assert_equal(['old'], known.map(&:message))
      assert_empty(fixed)
    end
  end

  def test_fixed_entries_are_listed
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'todo.yml')
      RequireHygiene::Baseline.write(file, [diagnostic('old')])
      _fresh, _known, fixed = RequireHygiene::Baseline.new(file).partition([])
      assert_equal(['lib/a.rb: unused_require: old'], fixed)
    end
  end

  def test_missing_file_means_no_known_findings
    fresh, = RequireHygiene::Baseline.new('/nonexistent.yml').partition([diagnostic('x')])
    assert_equal(1, fresh.length)
  end
end

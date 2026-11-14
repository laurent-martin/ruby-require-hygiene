# frozen_string_literal: true

require 'json'
require_relative 'test_helper'

class AnalyzerTest < Minitest::Test
  include TestHelper

  def analyze(*paths, **overrides)
    Dir.chdir(DEFECTS) do
      config = RequireHygiene::Configuration.load(nil, overrides)
      RequireHygiene::Analyzer.new(config).analyze(paths)
    end
  end

  def test_finds_missing_unused_and_duplicate
    report = analyze('lib/defects/c.rb')
    found = report.diagnostics.map { |d| [d.rule, d.line] }.sort
    assert_equal([['duplicate_require', 2], ['missing_require', 9], ['unused_require', 3]], found)
  end

  def test_missing_require_names_the_file_to_require
    message = analyze('lib/defects/c.rb').diagnostics.find { |d| d.rule.eql?('missing_require') }.message
    assert_includes(message, "add require 'defects/d'")
  end

  def test_facade_is_not_reported
    assert_empty(analyze('lib/defects.rb').diagnostics)
  end

  def test_minimum_confidence_hides_lower_findings
    all = analyze('lib/defects/c.rb')
    high = analyze('lib/defects/c.rb', 'output' => {'minimum_confidence' => 'high'})
    assert_operator(high.diagnostics.length, :<, all.diagnostics.length)
    assert(high.diagnostics.all? { |d| d.confidence.eql?('high') })
  end

  def test_report_is_json_ready
    hash = analyze('lib/defects/c.rb').to_h
    assert_equal(RequireHygiene::SCHEMA_VERSION, JSON.parse(JSON.generate(hash))['schema_version'])
    assert_equal(3, hash[:diagnostics].length)
  end

  def test_missing_path_is_an_error
    assert_raises(RequireHygiene::Error) { analyze('/nonexistent') }
  end

  def test_library_does_not_load_thor
    stdout, = Open3.capture2(RbConfig.ruby, '-I', File.join(ROOT, 'lib'), '-e', "require 'require_hygiene'; print defined?(Thor).inspect")
    assert_equal('nil', stdout)
  end
end

# frozen_string_literal: true

require_relative 'test_helper'

class ConfigurationTest < Minitest::Test
  include TestHelper

  def test_defaults
    config = RequireHygiene::Configuration.new
    assert_equal('self_contained', config.dig('policy', 'missing_requires'))
  end

  def test_file_and_overrides_are_merged_over_defaults
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'config.yml')
      File.write(file, "output:\n  format: json\n")
      config = RequireHygiene::Configuration.load(file, {'output' => {'minimum_confidence' => 'high'}})
      assert_equal(%w[json high], [config.dig('output', 'format'), config.dig('output', 'minimum_confidence')])
      assert_equal(['lib/**/*.rb'], config.dig('paths', 'include'))
    end
  end

  def test_missing_file_is_an_error
    assert_raises(RequireHygiene::ConfigurationError) { RequireHygiene::Configuration.load('/nonexistent.yml') }
  end

  def test_invalid_file_is_an_error
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'config.yml')
      File.write(file, "- a\n- b\n")
      assert_raises(RequireHygiene::ConfigurationError) { RequireHygiene::Configuration.load(file) }
    end
  end
end

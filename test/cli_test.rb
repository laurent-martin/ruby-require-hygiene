# frozen_string_literal: true

require_relative 'test_helper'

class CliTest < Minitest::Test
  include TestHelper

  def test_version
    stdout, _stderr, status = run_cli('version')
    assert_equal([RequireHygiene::VERSION, 0], [stdout.strip, status])
  end

  def test_version_option
    stdout, _stderr, status = run_cli('--version')
    assert_equal([RequireHygiene::VERSION, 0], [stdout.strip, status])
  end

  def test_analyze_text_exit_0_by_default
    stdout, _stderr, status = Dir.chdir(DEFECTS) { run_cli('analyze', 'lib/defects/c.rb') }
    assert_equal(0, status)
    assert_includes(stdout, 'missing_require')
    assert_includes(stdout, '3 finding(s)')
  end

  def test_fail_on_missing_exit_1
    _stdout, _stderr, status = Dir.chdir(DEFECTS) { run_cli('analyze', 'lib/defects/c.rb', '--fail-on', 'missing') }
    assert_equal(1, status)
  end

  def test_analyze_json
    stdout, _stderr, status = Dir.chdir(DEFECTS) { run_cli('analyze', 'lib/defects/c.rb', '--format', 'json') }
    assert_equal(0, status)
    assert_equal(3, JSON.parse(stdout)['diagnostics'].length)
  end

  def test_verbose_lists_requires
    stdout, = Dir.chdir(DEFECTS) { run_cli('analyze', 'lib/defects/c.rb', '--verbose') }
    assert_includes(stdout, 'require "defects/a"')
  end

  def test_baseline_hides_known_findings
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'todo.yml')
      Dir.chdir(DEFECTS) do
        _out, _err, status = run_cli('analyze', 'lib/defects/c.rb', '--write-baseline', '--baseline', file)
        assert_equal(0, status)
        _out, _err, status = run_cli('analyze', 'lib/defects/c.rb', '--baseline', file, '--fail-on', 'any')
        assert_equal(0, status)
      end
    end
  end

  def test_check_load
    stdout, _stderr, status = Dir.chdir(DEFECTS) { run_cli('check-load') }
    assert_equal(1, status)
    assert_includes(stdout, 'defects/c.rb')
  end

  def test_unknown_path_exit_status_is_2
    _stdout, stderr, status = run_cli('analyze', '/nonexistent')
    assert_equal(2, status)
    assert_match(/Error:/, stderr)
  end

  def test_invalid_option_value_is_not_a_findings_status
    _stdout, _stderr, status = run_cli('analyze', '--fail-on', 'bogus')
    refute_includes([0, 1], status)
  end
end

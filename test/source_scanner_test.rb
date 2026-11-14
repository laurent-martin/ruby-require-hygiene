# frozen_string_literal: true

require_relative 'test_helper'

class SourceScannerTest < Minitest::Test
  include TestHelper

  def info
    @info ||= RequireHygiene::SourceScanner.scan(File.join(ROOT, 'test/fixtures/directives/client.rb'))
  end

  def test_static_requires
    assert_equal(%w[set net/http optional_backend lazy_lib], info.requires.select(&:static?).map(&:path))
  end

  def test_dynamic_requires_have_no_invented_target
    dynamic = info.requires.reject(&:static?)
    assert_equal(3, dynamic.length)
    assert(dynamic.all? { |d| d.path.nil? })
  end

  def test_receiver_call_is_not_a_require
    refute(info.requires.any? { |d| d.path.eql?('not_kernel') })
  end

  def test_conditional_and_lazy_requires
    flags = info.requires.select(&:static?).to_h { |d| [d.path, [d.conditional?, d.lazy?]] }
    assert_equal({'set' => [false, false], 'net/http' => [true, false], 'optional_backend' => [true, false], 'lazy_lib' => [false, true]}, flags)
  end

  def test_location_is_one_based
    assert_equal([1, 1], [info.requires.first.line, info.requires.first.column])
  end

  def test_definitions_and_references
    assert_includes(info.defs, 'Sample::Client')
  end

  def test_syntax_error_is_an_error
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'broken.rb')
      File.write(file, "def x(\n")
      assert_raises(RequireHygiene::Error) { RequireHygiene::SourceScanner.scan(file) }
    end
  end
end

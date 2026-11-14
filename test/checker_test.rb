# frozen_string_literal: true

require_relative 'test_helper'

# Cases of the checker, on small fake `lib` folders
class CheckerTest < Minitest::Test
  include TestHelper

  BASE = {
    'my/error.rb' => "module My\n  class Error < StandardError; end\nend\n",
    'my/util.rb'  => "module My\n  module Util\n    def self.run; end\n  end\nend\n"
  }.freeze

  # @param files [Hash{String => String}] Path in lib => content
  # @return [Array<String>] Findings, as `file:rule:message`
  def findings(files)
    Dir.mktmpdir do |dir|
      files.each do |name, content|
        path = File.join(dir, name)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "# frozen_string_literal: true\n#{content}")
      end
      checked = Dir.glob(File.join(dir, '**/*.rb'))
      checker = RequireHygiene::Checker.new(load_paths: [dir], files: checked, root: dir)
      checker.check.map { |d| "#{d.file}:#{d.rule}:#{d.message}" }
    end
  end

  def test_accepts_a_file_that_requires_what_it_uses
    code = "require 'json'\nrequire 'my/error'\nmodule My\n  class A\n    def f = raise(Error, JSON.generate({}))\n  end\nend\n"
    assert_empty(findings(BASE.merge('my/a.rb' => code)))
  end

  def test_reports_a_require_of_the_folder_that_is_not_used
    code = "require 'my/error'\nrequire 'my/util'\nmodule My\n  class A\n    def f = raise(Error)\n  end\nend\n"
    result = findings(BASE.merge('my/a.rb' => code))
    assert_equal(1, result.length)
    assert_match(%r{my/a.rb:unused_require:require 'my/util'}, result.first)
  end

  def test_reports_a_require_of_a_library_that_is_not_used
    code = "require 'json'\nrequire 'securerandom'\nmodule My\n  class B\n    def f = JSON.generate({})\n  end\nend\n"
    result = findings(BASE.merge('my/b.rb' => code))
    assert_equal(1, result.length)
    assert_match(%r{my/b.rb:unused_require:require 'securerandom'}, result.first)
  end

  def test_reports_a_constant_of_the_folder_that_is_not_required_by_the_file_itself
    result = findings(BASE.merge('my/a.rb' => "module My\n  class A\n    def f = raise(Error)\n  end\nend\n"))
    assert_equal(1, result.length)
    assert_match(%r{my/a.rb:missing_require:My::Error is used.*add require 'my/error'}, result.first)
  end

  def test_reports_a_constant_provided_only_through_the_require_of_another_file
    result = findings(BASE.merge(
      'my/b.rb' => "require 'my/error'\nmodule My\n  class B; end\nend\n",
      'my/a.rb' => "require 'my/b'\nmodule My\n  class A < B\n    def f = raise(Error)\n  end\nend\n"
    ))
    assert_equal(['missing_require:My::Error'], result.filter_map { |r| r[/missing_require:\S+/] })
  end

  def test_follows_a_file_that_only_requires_other_files
    result = findings(BASE.merge(
      'my.rb'   => "require 'my/error'\nrequire 'my/util'\n",
      'my/a.rb' => "require 'my'\nmodule My\n  class A\n    def f = [Error, Util.run]\n  end\nend\n"
    ))
    assert_empty(result)
  end

  def test_takes_a_call_to_a_singleton_method_as_use_of_the_file
    code = "require 'my/util'\nmodule My\n  class A\n    def f = Util.run\n  end\nend\n"
    assert_empty(findings(BASE.merge('my/a.rb' => code)))
  end

  def test_reports_a_duplicate_require_at_top_of_file_and_a_require_in_a_method_that_repeats_one_at_top
    code = "require 'json'\nrequire 'json'\nmodule My\n  class A\n    def f\n      require 'json'\n      JSON.generate({})\n    end\n  end\nend\n"
    result = findings(BASE.merge('my/a.rb' => code))
    assert_equal(2, result.length)
    assert(result.all? { |r| r.include?(':duplicate_require:') })
  end

  def test_accepts_the_same_require_in_several_methods
    code = "module My\n  class A\n    def f\n      require 'securerandom'\n      SecureRandom.hex\n    end\n\n    def g\n      require 'securerandom'\n      SecureRandom.hex\n    end\n  end\nend\n"
    assert_empty(findings(BASE.merge('my/a.rb' => code)))
  end

  def test_reports_a_library_constant_used_through_another_library
    # `net/http` loads `uri`, but `URI` shall be required from `uri`
    result = findings(BASE.merge(
      'my/a.rb' => "require 'net/http'\nmodule My\n  class A\n    def f = [Net::HTTP, URI.parse('http://a')]\n  end\nend\n",
      'my/b.rb' => "require 'uri'\nmodule My\n  class B\n    def f = URI.parse('http://b')\n  end\nend\n"
    ))
    assert_equal(1, result.length)
    assert_match(%r{my/a.rb:missing_require:URI is used.*add require 'uri'}, result.first)
  end

  def test_does_not_take_defined_as_a_use
    assert_empty(findings(BASE.merge('my/a.rb' => "module My\n  class A\n    def f = defined?(Error)\n  end\nend\n")))
  end
end

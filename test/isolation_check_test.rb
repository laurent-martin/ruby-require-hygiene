# frozen_string_literal: true

require_relative 'test_helper'

class IsolationCheckTest < Minitest::Test
  include TestHelper

  def run_check(files, lib)
    RequireHygiene::IsolationCheck.run(files: files, load_paths: [lib])
  end

  def test_file_that_depends_on_load_order_fails
    lib = File.join(DEFECTS, 'lib')
    failures = run_check([File.join(lib, 'defects/c.rb'), File.join(lib, 'defects/a.rb')], lib)
    assert_equal(['defects/c.rb'], failures.map { |f| f.file.delete_prefix("#{lib}/") })
    refute(failures.first.optional)
  end

  def test_missing_library_is_optional
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'x.rb'), "require 'not_installed_library_xyz'\n")
      failures = run_check([File.join(dir, 'x.rb')], dir)
      assert_equal([true], failures.map(&:optional))
    end
  end
end

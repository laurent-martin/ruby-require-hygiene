# frozen_string_literal: true

require_relative 'test_helper'
require_relative '../examples/require_relative_first_cop'

# Cop of examples/require_relative_first_cop.rb
class RequireRelativeFirstCopTest < Minitest::Test
  COP = RuboCop::Cop::Style::RequireRelativeFirst

  # Run the cop on a source, with the autocorrection
  # @return [Array(Integer, String)] number of offenses, corrected source
  def run_cop(source, pinned: [])
    config = RuboCop::ConfigLoader.default_configuration.for_all_cops
    cop_config = RuboCop::Config.new({'AllCops' => config, 'Style/RequireRelativeFirst' => {'Pinned' => pinned}})
    processed = RuboCop::ProcessedSource.new(source, RUBY_VERSION.to_f, 'test.rb')
    cop = COP.new(cop_config, autocorrect: true, safe_autocorrect: false)
    report = RuboCop::Cop::Commissioner.new([cop]).investigate(processed)
    corrector = report.correctors.compact.first
    [report.offenses.size, corrector ? corrector.rewrite : source]
  end

  def test_moves_require_relative_before_require
    count, corrected = run_cop(<<~RUBY)
      require 'json'
      require_relative 'a'
      require 'uri'
      require_relative 'b'
    RUBY
    assert_equal(1, count)
    assert_equal(<<~RUBY, corrected)
      require_relative 'a'
      require_relative 'b'
      require 'json'
      require 'uri'
    RUBY
  end

  def test_accepts_good_order
    count, = run_cop(<<~RUBY)
      require_relative 'a'
      require 'json'
    RUBY
    assert_equal(0, count)
  end

  def test_blank_line_starts_a_new_block
    count, = run_cop(<<~RUBY)
      require 'json'

      require_relative 'a'
    RUBY
    assert_equal(0, count)
  end

  def test_comment_keeps_trailing_comment_and_ignores_nested_require
    count, corrected = run_cop(<<~RUBY)
      require 'json' # for parsing
      require_relative 'a'

      def lazy
        require 'uri'
        require_relative 'b'
      end
    RUBY
    assert_equal(1, count)
    assert_includes(corrected, "require_relative 'a'\nrequire 'json' # for parsing\n")
    assert_includes(corrected, "  require 'uri'\n  require_relative 'b'\n")
  end

  def test_pinned_stays_first
    count, corrected = run_cop(<<~RUBY, pinned: ['aspera/coverage'])
      require_relative '../lib/aspera/log'
      require 'aspera/coverage'
      require 'json'
    RUBY
    assert_equal(1, count)
    assert_equal(<<~RUBY, corrected)
      require 'aspera/coverage'
      require_relative '../lib/aspera/log'
      require 'json'
    RUBY
  end

  def test_not_safe_autocorrect
    refute(COP.new(RuboCop::Config.new, autocorrect: true).safe_autocorrect?)
  end
end

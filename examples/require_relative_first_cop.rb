# frozen_string_literal: true

require 'rubocop'

module RuboCop
  module Cop
    module Style
      # Puts `require_relative` before `require` in each block of consecutive top-level `require` lines.
      #
      # Why: `require` is global to the process. A gem or standard library loaded by an earlier line can hide the
      # fact that a local file does not require what it uses. Loading the local files first makes such a missing
      # dependency fail at load time, as the local file is loaded before the `require` of its caller.
      # This is only a help: the reliable check is `require_hygiene check-load` (each file loaded alone).
      #
      # A block is a series of `require` / `require_relative` lines with a string argument, each alone on its line,
      # with no blank line, comment or other code between them. The order inside each kind is kept (stable).
      # `require` in a method, a condition or a `begin/rescue` is not touched.
      #
      # Files that must be loaded before any other (for example the code coverage) are listed in `Pinned`: they
      # stay first, whatever their kind. A pinned entry matches the whole argument or its last path segments.
      #
      # @safety
      #   The autocorrection is unsafe, because it changes the load order: it requires `-A`.
      #
      # @example
      #   # bad
      #   require 'json'
      #   require_relative 'models/user'
      #
      #   # good
      #   require_relative 'models/user'
      #   require 'json'
      #
      # Configuration in .rubocop.yml:
      #   require:
      #     - ./examples/require_relative_first_cop.rb
      #   Style/RequireRelativeFirst:
      #     Enabled: true
      #     Pinned:
      #       - aspera/coverage
      class RequireRelativeFirst < Base
        extend AutoCorrector

        include RangeHelp

        MSG = 'Put `require_relative` before `require`, and keep the pinned files first.'

        # @!method simple_require?(node)
        def_node_matcher :simple_require?, <<~PATTERN
          (send nil? {:require :require_relative} (str _))
        PATTERN

        def on_new_investigation
          root = processed_source.ast
          return unless root&.begin_type?

          sections(root.children).each { |section| check_section(section) }
        end

        # Not corrected by `-a`, only by `-A`
        def safe_autocorrect?
          false
        end

        private

        # Series of consecutive lines holding a simple `require` or `require_relative`
        def sections(nodes)
          result = []
          previous = nil
          nodes.each do |node|
            unless own_line?(node)
              previous = nil
              next
            end
            if previous && node.first_line == previous.last_line + 1
              result.last << node
            else
              result << [node]
            end
            previous = node
          end
          result
        end

        def own_line?(node)
          return false unless node.is_a?(AST::Node) && simple_require?(node)

          range = node.source_range
          begins_its_line?(range) && range.source_buffer.source_line(range.last_line)[range.last_column..].match?(/\A\s*(#.*)?\z/)
        end

        def check_section(section)
          sorted = section.each_with_index.sort_by { |node, index| [rank(node), index] }.map(&:first)
          position = section.each_index.find { |i| !sorted[i].equal?(section[i]) }
          return unless position

          add_offense(sorted[position]) do |corrector|
            range = range_by_whole_lines(section.first.source_range.join(section.last.source_range), include_final_newline: false)
            corrector.replace(range, sorted.map { |node| processed_source.lines[node.first_line - 1] }.join("\n"))
          end
        end

        # 0: pinned, 1: require_relative, 2: require
        def rank(node)
          return 0 if pinned?(node.first_argument.value)

          node.method?(:require_relative) ? 1 : 2
        end

        def pinned?(path)
          cop_config.fetch('Pinned', []).any? { |pinned| path == pinned || path.end_with?("/#{pinned}") }
        end
      end
    end
  end
end

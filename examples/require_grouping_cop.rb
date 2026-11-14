# frozen_string_literal: true

require 'rbconfig'
require 'rubocop'

module RuboCop
  module Cop
    module Style
      # Checks that the `require` lines at the top level of a file are grouped by origin, sorted, and separated by a
      # blank line: standard library, then gems, then internal files.
      #
      # Origin of a `require`:
      # - internal: `require_relative`, or `require` of a file found in `LoadPaths`;
      # - standard library: `require` of a file found in the library directories of the running Ruby
      #   (`RbConfig::CONFIG['rubylibdir']`, `['rubyarchdir']`), or listed in `ExtraStandardLibrary`;
      # - gem: any other `require`.
      #
      # Only blocks of consecutive `require` lines are checked. A line that is conditional (`require 'a' if b`), dynamic
      # (`require name`), followed by another statement, or with a comment on the line above ends the block: it is never
      # moved, and no comment is lost by the autocorrection.
      #
      # @safety
      #   The autocorrection is unsafe: it changes the order in which the files are loaded. Review the result.
      #
      # @example
      #   # bad
      #   require_relative 'models/user'
      #   require 'nokogiri'
      #   require 'json'
      #   require 'faraday'
      #
      #   # good
      #   require 'json'
      #
      #   require 'faraday'
      #   require 'nokogiri'
      #
      #   require_relative 'models/user'
      #
      # Configuration in .rubocop.yml:
      #   require:
      #     - ./examples/require_grouping_cop.rb
      #   Style/RequireGrouping:
      #     Enabled: true
      #     LoadPaths:
      #       - lib
      #     ExtraStandardLibrary:
      #       - set
      #     Sort: true
      class RequireGrouping < Base
        extend AutoCorrector
        include RangeHelp

        MSG_GROUP = 'Group `require` lines by origin: standard library, then gems, then internal files.'
        MSG_SORT = 'Sort `require` lines in alphabetical order within each group.'
        MSG_BLANK = 'Separate the groups of `require` lines with one blank line, and leave no blank line inside a group.'

        GROUPS = %i[standard_library gem internal].freeze
        METHODS = %i[require require_relative].freeze

        Entry = Struct.new(:node, :line, :path, :group)

        def on_new_investigation
          ast = processed_source.ast
          return unless ast

          statements = ast.begin_type? ? ast.children : [ast]
          blocks(statements).each { |block| check_block(block) }
        end

        private

        # Blocks of consecutive plain `require` lines. Anything else ends the current block.
        def blocks(statements)
          result = []
          current = []
          statements.each do |statement|
            entry = entry_for(statement)
            if entry.nil? || (current.any? && !adjacent?(current.last, entry))
              result << current
              current = []
            end
            current << entry if entry
          end
          result << current
          result.reject { |block| block.size < 2 }
        end

        def entry_for(node)
          return unless node.is_a?(AST::Node) && node.send_type? && node.receiver.nil? && METHODS.include?(node.method_name)
          return unless node.arguments.size == 1 && node.first_argument.str_type?
          return unless alone_on_its_line?(node)
          return if comment_above?(node)

          path = node.first_argument.value
          Entry.new(node, processed_source.lines[node.first_line - 1], path, group_of(node.method_name, path))
        end

        # Single line, nothing before it, and nothing after it except a comment
        def alone_on_its_line?(node)
          return false unless node.single_line? && begins_its_line?(node.source_range)

          range = node.source_range
          processed_source.lines[node.first_line - 1][range.last_column..].match?(/\A\s*(#.*)?\z/)
        end

        # A comment right above a line belongs to it: the line is never moved
        def comment_above?(node)
          node.first_line > 1 && processed_source.lines[node.first_line - 2].strip.start_with?('#')
        end

        # Only blank lines between two lines of the same block, so that no comment is dropped
        def adjacent?(previous, entry)
          between = processed_source.lines[previous.node.last_line...(entry.node.first_line - 1)]
          between.all? { |line| line.strip.empty? }
        end

        def group_of(method_name, path)
          if method_name == :require_relative || internal_file?(path)
            :internal
          elsif standard_library?(path)
            :standard_library
          else
            :gem
          end
        end

        def internal_file?(path)
          cop_config.fetch('LoadPaths', ['lib']).any? { |load_path| File.file?(File.expand_path("#{path}.rb", load_path)) }
        end

        def standard_library?(path)
          return true if cop_config.fetch('ExtraStandardLibrary', ['set']).include?(path)

          extensions = ['rb', RbConfig::CONFIG['DLEXT']]
          directories = [RbConfig::CONFIG['rubylibdir'], RbConfig::CONFIG['rubyarchdir']]
          directories.product(extensions).any? { |directory, extension| File.file?(File.join(directory, "#{path}.#{extension}")) }
        end

        def check_block(block)
          expected = sorted(block)
          expected_text = render(expected)
          first = block.first.node.source_range
          range = range_by_whole_lines(first.join(block.last.node.source_range))
          return if range.source == expected_text

          add_offense(first.join(block.last.node.source_range), message: message_for(block, expected)) do |corrector|
            corrector.replace(range, expected_text)
          end
        end

        def sorted(block)
          sort = cop_config.fetch('Sort', true)
          block.each_with_index.sort_by { |entry, index| [GROUPS.index(entry.group), sort ? entry.path : '', index] }.map(&:first)
        end

        # One blank line between groups
        def render(entries)
          entries.chunk(&:group).map { |_group, group_entries| group_entries.map(&:line).join("\n") }.join("\n\n")
        end

        def message_for(block, expected)
          groups = block.map { |entry| GROUPS.index(entry.group) }
          if groups != groups.sort
            MSG_GROUP
          elsif block != expected
            MSG_SORT
          else
            MSG_BLANK
          end
        end
      end
    end
  end
end

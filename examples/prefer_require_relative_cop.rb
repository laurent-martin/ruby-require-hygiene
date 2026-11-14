# frozen_string_literal: true

require 'rubocop'
require 'pathname'

module RuboCop
  module Cop
    module Style
      # Detects `require` calls targeting internal files of the gem/project
      # and suggests or autocorrects them to `require_relative`.
      #
      # @example
      #   # In lib/my_gem/sub/feature.rb
      #   # bad
      #   require 'my_gem/version'
      #
      #   # good
      #   require_relative '../version'
      #
      # Configuration in .rubocop.yml:
      #   require:
      #     - ./examples/prefer_require_relative_cop.rb
      #   Style/PreferRequireRelative:
      #     Enabled: true
      #     LoadPaths:
      #       - lib
      class PreferRequireRelative < Base
        extend AutoCorrector

        MSG = "Prefer `require_relative '%<relative_path>s'` over `require '%<original_path>s'` for internal files."
        RESTRICT_ON_SEND = %i[require].freeze

        def_node_matcher :require_call?, <<~PATTERN
          (send nil? :require (str $_))
        PATTERN

        def on_send(node)
          require_call?(node) do |required_path|
            current_file = processed_source.file_path
            return if current_file.nil? || current_file == '(string)'

            load_paths = cop_config.fetch('LoadPaths', ['lib'])
            target_file = resolve_internal_file(required_path, load_paths)
            return unless target_file

            rel_path = compute_relative_path(current_file, target_file)

            message = format(MSG, relative_path: rel_path, original_path: required_path)
            add_offense(node, message: message) do |corrector|
              corrector.replace(node, "require_relative '#{rel_path}'")
            end
          end
        end

        private

        def resolve_internal_file(path, load_paths)
          load_paths.each do |lp|
            candidate = File.expand_path("#{path}.rb", lp)
            return candidate if File.file?(candidate)
          end
          nil
        end

        def compute_relative_path(from_file, to_file)
          from_dir = Pathname.new(File.dirname(File.expand_path(from_file)))
          to_path = Pathname.new(to_file)
          rel = to_path.relative_path_from(from_dir).to_s
          # Strip .rb extension
          rel.delete_suffix('.rb')
        end
      end
    end
  end
end

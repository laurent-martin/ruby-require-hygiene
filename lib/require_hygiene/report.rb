# frozen_string_literal: true

require_relative 'diagnostic'

module RequireHygiene
  # Result of an analysis
  class Report
    # @return [Array<String>] Files analyzed
    attr_reader :files
    # @return [Array<RequireDirective>] Static and dynamic requires found
    attr_reader :directives
    # @return [Array<Diagnostic>] Findings
    attr_reader :diagnostics
    # @return [Array<String>] Rules that were executed
    attr_reader :rules

    def initialize(files:, directives:, diagnostics:, rules:)
      @files = files.freeze
      @directives = directives.freeze
      @diagnostics = diagnostics.freeze
      @rules = rules.freeze
      freeze
    end

    # @return [Hash] JSON-ready
    def to_h
      {
        schema_version: SCHEMA_VERSION,
        rules:          rules,
        files:          files,
        requires:       directives.map(&:to_h),
        diagnostics:    diagnostics.map(&:to_h)
      }
    end
  end
end

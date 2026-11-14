# frozen_string_literal: true

require 'yaml'

module RequireHygiene
  # Known findings to fix progressively, like `.rubocop_todo.yml`: only new findings are reported.
  # An entry has no line number, so that it does not change when code moves.
  class Baseline
    # Default file name
    DEFAULT_FILE = '.require_hygiene_todo.yml'
    # Comment at the top of the file
    HEADER = "# Known findings of `require_hygiene analyze`. Remove entries when fixed.\n"

    class << self
      # @param diagnostic [Diagnostic]
      # @return [String] Key of the finding in the file
      def key(diagnostic)
        "#{diagnostic.file}: #{diagnostic.rule}: #{diagnostic.message}"
      end

      # @param file [String] File to write
      # @param diagnostics [Array<Diagnostic>] Findings to record
      # @return [Integer] Number of entries
      def write(file, diagnostics)
        keys = diagnostics.map { |diagnostic| key(diagnostic) }.uniq.sort
        File.write(file, "#{HEADER}#{keys.to_yaml.delete_prefix("---\n")}")
        keys.length
      end
    end

    # @param file [String, nil] Baseline file, missing or nil: no known findings
    def initialize(file = nil)
      @known = file && File.file?(file) ? Array(YAML.safe_load_file(file)) : []
    end

    # @param diagnostics [Array<Diagnostic>]
    # @return [Array(Array<Diagnostic>, Array<Diagnostic>, Array<String>)] new findings, known findings, entries that are fixed
    def partition(diagnostics)
      known, fresh = diagnostics.partition { |diagnostic| @known.include?(self.class.key(diagnostic)) }
      [fresh, known, @known - diagnostics.map { |diagnostic| self.class.key(diagnostic) }]
    end
  end
end

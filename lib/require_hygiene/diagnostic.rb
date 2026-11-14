# frozen_string_literal: true

module RequireHygiene
  # Version of the JSON schema of {Diagnostic#to_h} and {Report#to_h}
  SCHEMA_VERSION = 1

  # One finding, independent of the analysis backend. Lines and columns start at 1.
  # `rule` is `missing_require` or `unused_require`, `confidence` is `low`, `medium` or `high`,
  # `severity` is `info`, `warning` or `error`, `subject` and `evidence` are Hashes of plain values.
  Diagnostic = Struct.new(:rule, :file, :line, :column, :confidence, :severity, :message, :subject, :evidence, keyword_init: true) do
    # @return [Hash] JSON-ready, see the JSON diagnostic schema in the specification
    def to_h
      {
        schema_version: SCHEMA_VERSION,
        rule:           rule,
        file:           file,
        location:       {start_line: line, start_column: column},
        confidence:     confidence,
        severity:       severity,
        subject:        subject || {},
        evidence:       evidence || {},
        message:        message
      }
    end
  end
end

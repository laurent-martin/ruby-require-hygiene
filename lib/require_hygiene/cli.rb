# frozen_string_literal: true

require 'json'
require 'thor'
require_relative '../require_hygiene'

module RequireHygiene
  # Command line, a thin adapter on the library: parse options, call {Analyzer}, print, set the exit status.
  # Only `bin/require_hygiene` loads this file.
  class CLI < Thor
    # Exit status: no failing finding
    EXIT_OK = 0
    # Exit status: at least one finding at or above the `--fail-on` threshold
    EXIT_FINDINGS = 1
    # Exit status: usage, configuration or analysis error
    EXIT_ERROR = 2
    # Values of `--fail-on`
    FAIL_ON = %w[never missing unused duplicate warning any].freeze

    # Raised by a command to end with {EXIT_FINDINGS}, see {start}
    class Findings < StandardError; end

    class << self
      def exit_on_failure?
        true
      end

      # Thor exits with status 1 on a usage error, which would be taken for "findings": the status of this tool is 2
      def start(given_args = ARGV, config = {})
        super
      rescue Findings
        exit(EXIT_FINDINGS)
      rescue SystemExit => e
        exit(e.success? ? EXIT_OK : EXIT_ERROR)
      end
    end

    map %w[--version -v] => :version

    desc 'analyze [PATH...]', 'Find missing, unused and duplicate requires (default: paths of the configuration, lib/**/*.rb)'
    method_option :config, aliases: '-c', type: :string, desc: 'Configuration file (default: .require_hygiene.yml if present)'
    method_option :format, aliases: '-f', type: :string, enum: %w[text json], desc: 'Output format (default: text)'
    method_option :min_confidence, type: :string, enum: Configuration::CONFIDENCES, desc: 'Hide findings below this confidence'
    method_option :fail_on, type: :string, default: 'never', enum: FAIL_ON, desc: 'Exit with status 1 when such a new finding exists'
    method_option :baseline, type: :string, desc: "Known findings file, not reported (default: baseline.file of the configuration)"
    method_option :write_baseline, type: :boolean, default: false, desc: "Record the current findings in the baseline file (#{Baseline::DEFAULT_FILE} by default)"
    method_option :verbose, aliases: '-V', type: :boolean, default: false, desc: 'Also list the files and the requires found'
    def analyze(*paths)
      config = load_configuration
      report = Analyzer.new(config).analyze(paths)
      baseline_file = options[:baseline] || config.dig('baseline', 'file')
      return write_baseline(report, baseline_file || Baseline::DEFAULT_FILE) if options[:write_baseline]
      fresh, known, fixed = Baseline.new(baseline_file).partition(report.diagnostics)
      shown = Report.new(files: report.files, directives: report.directives, diagnostics: fresh, rules: report.rules)
      puts(config.dig('output', 'format').eql?('json') ? JSON.pretty_generate(shown.to_h) : text(shown, known.length, fixed))
      raise Findings unless exit_status(fresh, options[:fail_on]).zero?
    rescue RequireHygiene::Error => e
      say_error("Error: #{e.message}")
      exit(EXIT_ERROR)
    end

    desc 'check-load [PATH...]', 'Load each file alone in a new Ruby process, to find files that depend on the load order'
    method_option :config, aliases: '-c', type: :string, desc: 'Configuration file (default: .require_hygiene.yml if present)'
    method_option :format, aliases: '-f', type: :string, enum: %w[text json], desc: 'Output format (default: text)'
    def check_load(*paths)
      config = load_configuration
      analyzer = Analyzer.new(config)
      files = analyzer.source_files(paths)
      failures = IsolationCheck.run(files: files, load_paths: analyzer.load_paths)
      errors = failures.reject(&:optional)
      if config.dig('output', 'format').eql?('json')
        puts(JSON.pretty_generate(files: files.length, failures: failures.map(&:to_h)))
      else
        failures.each { |f| puts("#{f.file}: #{f.optional ? 'not loaded, optional library missing' : 'cannot be loaded alone'}: #{f.message.lines.first.chomp}") }
        puts("#{files.length - failures.length} file(s) loaded alone, #{failures.length - errors.length} skipped (optional library), #{errors.length} error(s)")
      end
      raise Findings unless errors.empty?
    rescue RequireHygiene::Error => e
      say_error("Error: #{e.message}")
      exit(EXIT_ERROR)
    end

    desc 'version', 'Show the version'
    def version
      puts(VERSION)
    end

    private

    def load_configuration
      overrides = {}
      overrides['output'] = {'format' => options[:format]} if options[:format]
      (overrides['output'] ||= {})['minimum_confidence'] = options[:min_confidence] if options[:min_confidence]
      Configuration.load(options[:config], overrides)
    end

    def write_baseline(report, file)
      puts("Recorded #{Baseline.write(file, report.diagnostics)} finding(s) in #{file}")
    end

    # @return [Integer] exit status
    def exit_status(findings, fail_on)
      failing = findings.select do |finding|
        case fail_on
        when 'missing' then finding.rule.eql?('missing_require')
        when 'unused' then finding.rule.eql?('unused_require')
        when 'duplicate' then finding.rule.eql?('duplicate_require')
        when 'warning' then finding.severity.eql?('warning')
        when 'any' then true
        else false
        end
      end
      failing.empty? ? EXIT_OK : EXIT_FINDINGS
    end

    # @return [String] human-readable report
    def text(report, known_count, fixed)
      lines = report.diagnostics.map { |d| "#{d.file}:#{d.line}:#{d.column}: #{d.rule} (#{d.confidence}) #{d.message}" }
      fixed.each { |key| lines.push("Baseline: fixed, remove: #{key}") }
      if options[:verbose]
        lines.push("Files analyzed: #{report.files.length}")
        report.directives.each do |d|
          lines.push("#{d.file}:#{d.line}:#{d.column}: #{d.kind} #{d.path ? d.path.inspect : '(dynamic)'}#{' [conditional]' if d.conditional?}#{' [lazy]' if d.lazy?}")
        end
      end
      lines.push("#{report.diagnostics.length} finding(s) in #{report.files.length} file(s)#{", #{known_count} known (baseline)" if known_count.positive?}")
      lines.join("\n")
    end
  end
end

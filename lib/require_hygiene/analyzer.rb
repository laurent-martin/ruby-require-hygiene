# frozen_string_literal: true

require_relative 'checker'
require_relative 'configuration'
require_relative 'errors'
require_relative 'report'

module RequireHygiene
  # Entry point of the library: analyzes files and returns a {Report}. It never prints and never exits.
  class Analyzer
    # Rules that produce diagnostics
    RULES = %w[missing_require unused_require duplicate_require].freeze

    # @param configuration [Configuration]
    def initialize(configuration = Configuration.load)
      @configuration = configuration
    end

    # @param paths [Array<String>] Files or folders, default: the `paths.include` patterns of the configuration
    # @return [Report]
    # @raise [Error] if a path does not exist or a file cannot be parsed
    def analyze(paths = [])
      files = source_files(paths)
      checker = Checker.new(
        load_paths:     load_paths,
        files:          files,
        root:           Dir.pwd,
        extra_provides: @configuration.dig('allow', 'extra_provides'),
        usage_patterns: @configuration.usage_patterns
      )
      diagnostics = checker.check.select { |diagnostic| confident?(diagnostic) }
      Report.new(files: files, directives: checker.checked_infos.flat_map(&:requires), diagnostics: diagnostics, rules: RULES)
    end

    # @return [Array<String>] Folders of the load path
    def load_paths
      @configuration.dig('paths', 'load_paths').select { |path| File.directory?(path) }
    end

    # @param paths [Array<String>] Files or folders, default: the `paths.include` patterns of the configuration
    # @return [Array<String>] Files to check
    # @raise [Error] if there is none
    def source_files(paths)
      patterns = paths.empty? ? @configuration.dig('paths', 'include') : paths.map { |path| File.directory?(path) ? File.join(path, '**', '*.rb') : path }
      files = patterns.flat_map { |pattern| File.exist?(pattern) ? [pattern] : Dir.glob(pattern) }.reject { |file| excluded?(file) }.uniq.sort
      raise Error, "No Ruby file found for: #{(paths.empty? ? patterns : paths).join(', ')}" if files.empty?
      files
    end

    private

    def confident?(diagnostic)
      levels = Configuration::CONFIDENCES
      levels.index(diagnostic.confidence) >= levels.index(@configuration.dig('output', 'minimum_confidence'))
    end

    def excluded?(file)
      @configuration.dig('paths', 'exclude').any? { |pattern| File.fnmatch?(pattern, file, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
    end
  end
end

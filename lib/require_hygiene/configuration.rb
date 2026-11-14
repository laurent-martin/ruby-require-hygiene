# frozen_string_literal: true

require 'yaml'
require_relative 'errors'

module RequireHygiene
  # Immutable settings: defaults, then a YAML file, then explicit overrides
  class Configuration
    # Name of the configuration file looked up in the current folder
    DEFAULT_FILE = '.require_hygiene.yml'
    # Settings and their default value
    DEFAULTS = {
      # `load_paths`: folders where `require 'a/b'` is `a/b.rb`. `exclude`: files not checked, but still used to resolve constants
      'paths'    => {'include' => ['lib/**/*.rb'], 'exclude' => [], 'load_paths' => ['lib']},
      'policy'   => {'missing_requires' => 'self_contained'},
      # `extra_provides`: require name => constants it provides. `usage_patterns`: require name => regular expression of its use
      'allow'    => {'extra_provides' => {}, 'usage_patterns' => {}},
      'baseline' => {'file' => nil},
      'output'   => {'format' => 'text', 'minimum_confidence' => 'low'}
    }.freeze
    # Confidence levels, from the lowest
    CONFIDENCES = %w[low medium high].freeze

    # @return [Hash] settings, frozen
    attr_reader :settings

    class << self
      # @param file      [String, nil] YAML file, default: {DEFAULT_FILE} if it exists, else defaults only
      # @param overrides [Hash]        Settings that win over the file, same structure as the file
      # @return [Configuration]
      # @raise [ConfigurationError] if the file is missing (when given), not valid YAML, or not a mapping
      def load(file = nil, overrides = {})
        file ||= DEFAULT_FILE if File.exist?(DEFAULT_FILE)
        from_file = file.nil? ? {} : read(file)
        new(deep_merge(deep_merge(DEFAULTS, from_file), overrides))
      end

      private

      def read(file)
        raise ConfigurationError, "Configuration file not found: #{file}" unless File.file?(file)
        data = YAML.safe_load_file(file) || {}
        raise ConfigurationError, "Configuration must be a mapping: #{file}" unless data.is_a?(Hash)
        data
      rescue Psych::Exception => e
        raise ConfigurationError, "Invalid configuration #{file}: #{e.message}"
      end

      def deep_merge(base, other)
        base.merge(other) { |_key, old, new| old.is_a?(Hash) && new.is_a?(Hash) ? deep_merge(old, new) : new }
      end
    end

    # @param settings [Hash] Complete settings
    def initialize(settings = DEFAULTS)
      @settings = settings.freeze
      freeze
    end

    # @param keys [Array<String>] Path of the setting, e.g. `'output', 'format'`
    # @return [Object, nil] The setting
    def dig(*keys)
      @settings.dig(*keys)
    end

    # @return [Hash{String => Regexp}] `allow.usage_patterns`, compiled
    # @raise [ConfigurationError] if a pattern is not a valid regular expression
    def usage_patterns
      dig('allow', 'usage_patterns').transform_values { |pattern| Regexp.new(pattern) }
    rescue RegexpError => e
      raise ConfigurationError, "Invalid allow.usage_patterns: #{e.message}"
    end
  end
end

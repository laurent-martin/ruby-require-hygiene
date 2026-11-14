# frozen_string_literal: true

require 'open3'
require 'pathname'
require 'rbconfig'
require_relative 'workers'

module RequireHygiene
  # Loads each file alone in a new Ruby process, to find files that work only thanks to the load order.
  # Complements the static analysis, see the specification.
  module IsolationCheck
    # A file that cannot be loaded alone.
    # `optional` is true when the cause is a library that is not installed (not a file of the analyzed gem).
    Failure = Struct.new(:file, :message, :optional, keyword_init: true) do
      # @return [Hash] JSON-ready
      def to_h
        {file: file, message: message, optional: optional}
      end
    end

    # Error of Ruby for a file that is not found
    MISSING_FILE = /cannot load such file -- (\S+)/

    class << self
      # @param files      [Array<String>] Files to load, each one alone
      # @param load_paths [Array<String>] Folders in the load path, where `require 'a/b'` is `a/b.rb`
      # @return [Array<Failure>] Files that cannot be loaded, sorted by name
      def run(files:, load_paths:)
        paths = load_paths.map { |path| Pathname.new(path).expand_path }
        outputs = Workers.map(files) { |file| load_alone(file, paths) }
        outputs.compact.sort_by(&:file)
      end

      private

      def load_alone(file, paths)
        args = paths.flat_map { |path| ['-I', path.to_s] }
        out, status = unbundled { Open3.capture2e(RbConfig.ruby, *args, '-e', 'require ARGV[0]', File.expand_path(file)) }
        return if status.success?
        missing = out[MISSING_FILE, 1]
        Failure.new(file: file, message: out.lines.first(5).join.chomp, optional: !missing.nil? && paths.none? { |path| (path / "#{missing}.rb").file? })
      end

      def unbundled(&block)
        defined?(Bundler) ? Bundler.with_unbundled_env(&block) : yield
      end
    end
  end
end

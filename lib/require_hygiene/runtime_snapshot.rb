# frozen_string_literal: true

require 'json'
require 'open3'
require 'rbconfig'
require_relative 'workers'

module RequireHygiene
  # Constants that a library adds, found by loading it in a new Ruby process.
  # This executes the code of the library: only libraries that the analyzed files already require are loaded.
  module RuntimeSnapshot
    # What a library adds when it is loaded. `constants` are full names, `files` the paths added to `$LOADED_FEATURES`.
    Result = Struct.new(:constants, :files)

    # Ruby script that prints two JSON lines: the constants (full name, up to a depth) and the files loaded by the require of
    # its first argument (without argument: all the constants of a bare Ruby)
    SCRIPT = <<~RUBY
      def snap(mod, prefix, depth, seen, out)
        mod.constants(false).each do |c|
          full = prefix ? "\#{prefix}::\#{c}" : c.to_s
          out << full
          next if depth >= 5 || mod.autoload?(c)
          value = begin; mod.const_get(c, false); rescue Exception; next; end
          next unless value.is_a?(Module) && !seen.key?(value)
          seen[value] = true
          snap(value, full, depth + 1, seen, out)
        end
        out
      end
      take = -> { snap(Object, nil, 0, {Object => true}.compare_by_identity, []) }
      before = take.call
      features = $LOADED_FEATURES.dup
      require ARGV[0] if ARGV[0]
      # No JSON library here: it would hide the constants of `json`
      puts "[\#{(ARGV[0] ? take.call - before : before).map(&:inspect).join(',')}]"
      puts "[\#{($LOADED_FEATURES - features).map(&:inspect).join(',')}]"
    RUBY

    class << self
      # @param library [String, nil] Name given to `require`, or nil for the constants of a bare Ruby
      # @return [Result, nil] nil if the library cannot be loaded (optional gem that is not installed: not an error here)
      def load(library = nil)
        # Outside Bundler: it would load the analyzed gem (gemspec), and its constants would be taken as provided by Ruby
        out, _err, status = unbundled { Open3.capture3(RbConfig.ruby, '-e', SCRIPT, *library) }
        Result.new(*out.lines.first(2).map { |line| JSON.parse(line) }) if status.success?
      end

      # @return [Array<String>] All the constants of a bare Ruby
      def core_constants
        load.constants
      end

      # @param libraries [Array<String>]
      # @return [Hash{String => Result, nil}] Result for each library, in parallel
      def many(libraries)
        libraries.zip(Workers.map(libraries) { |library| load(library) }).to_h
      end

      private

      def unbundled(&block)
        defined?(Bundler) ? Bundler.with_unbundled_env(&block) : yield
      end
    end
  end
end

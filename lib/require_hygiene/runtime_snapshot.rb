# frozen_string_literal: true

require 'json'
require 'open3'
require 'rbconfig'
require_relative 'workers'

module RequireHygiene
  # Constants that a library adds, found by loading it in a new Ruby process.
  # This executes the code of the library: only libraries that the analyzed files already require, and libraries of Ruby
  # ({Checker::STANDARD_LIBRARIES}), are loaded.
  module RuntimeSnapshot
    # What a library adds when it is loaded. `constants` are full names. `owners`: for each constant, the names given to the
    # `require` calls in progress when it appeared, outermost first (the library itself, then the libraries it loads):
    # `require 'psych'` gives `Date => ['psych', 'date', 'date_core']`.
    Result = Struct.new(:constants, :owners)

    # Ruby script that prints two JSON lines: the constants (full name, up to a depth) added by the require of its first argument
    # (without argument: all the constants of a bare Ruby), and their owners. `require` is traced: after each one, the new
    # constants are taken as added by the stack of requires in progress (`require_relative` is part of the require that calls it).
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
      $rh_take = -> { snap(Object, nil, 0, {Object => true}.compare_by_identity, []) }
      # Constants that appeared since the last call: added by the requires in progress
      def rh_flush
        now = $rh_take.call
        (now - $rh_seen).each { |c| $rh_owners[c] = $rh_stack.dup }
        $rh_seen = now
      end
      # Defined before the first snapshot: not a constant of the library
      module RequireHygieneTrace
        private def require(name)
          # Before the nested require: what the file in progress defined so far is its own
          rh_flush
          $rh_stack.push(name.to_s)
          super
        ensure
          rh_flush
          $rh_stack.pop
        end
      end
      before = $rh_take.call
      if ARGV[0]
        $rh_seen = before
        $rh_stack = []
        $rh_owners = {}
        Kernel.prepend(RequireHygieneTrace)
        require ARGV[0]
      end
      # No JSON library here: it would hide the constants of `json`
      puts "[\#{(ARGV[0] ? $rh_seen - before : before).map(&:inspect).join(',')}]"
      puts "{\#{(ARGV[0] ? $rh_owners : {}).map { |c, s| "\#{c.inspect}:[\#{s.map(&:inspect).join(',')}]" }.join(',')}}"
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
      # @return [Hash{String => Result, nil}] Result for each library, in parallel. Kept for the life of the process
      #   (same Ruby, same libraries): each library is loaded once.
      def many(libraries)
        @cache ||= {}
        todo = libraries.uniq.reject { |library| @cache.key?(library) }
        @cache.merge!(todo.zip(Workers.map(todo) { |library| load(library) }).to_h)
        libraries.to_h { |library| [library, @cache[library]] }
      end

      private

      def unbundled(&block)
        defined?(Bundler) ? Bundler.with_unbundled_env(&block) : yield
      end
    end
  end
end

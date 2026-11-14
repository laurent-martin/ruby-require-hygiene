# frozen_string_literal: true

module RequireHygiene
  # A call to `require` or `require_relative` found in a source file.
  # `path` is nil when the argument is not a plain string (dynamic loading): no target is ever invented.
  # `conditional` is true under `if`, `unless`, a modifier or `rescue` (optional feature), `lazy` inside a method.
  # Lines and columns start at 1.
  RequireDirective = Struct.new(:file, :kind, :path, :line, :column, :conditional, :lazy, keyword_init: true) do
    # @return [Boolean] true if the argument is a literal string
    def static?
      !path.nil?
    end

    # @return [Boolean] true for `require_relative`
    def relative?
      kind.eql?(:require_relative)
    end

    alias_method :conditional?, :conditional
    alias_method :lazy?, :lazy

    # @return [Hash] JSON-ready
    def to_h
      {file: file, kind: kind, path: path, line: line, column: column, static: static?, conditional: conditional, lazy: lazy}
    end
  end
end

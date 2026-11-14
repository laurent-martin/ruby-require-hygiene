# frozen_string_literal: true

require 'pathname'
require 'prism'
require_relative 'errors'
require_relative 'require_directive'

module RequireHygiene
  # What a scan of one Ruby file found. Lines and columns start at 1.
  # `defs` are the full names of the constants defined, `refs` the constants used, `calls` the methods called (name => first line and column),
  # `singleton_methods` are `Foo.bar` and `instance_methods` map a class or module name to the names of its methods.
  SourceInfo = Struct.new(:path, :requires, :defs, :refs, :calls, :singleton_methods, :instance_methods, :source, keyword_init: true) do
    # @return [Boolean] true if the file only requires other files (a facade, e.g. an aggregate entry point)
    def facade?
      !requires.empty? && defs.empty? && singleton_methods.empty? && instance_methods.empty?
    end
  end

  # Reference to a constant, and optionally a singleton method called on it. `crefs` is the lexical nesting.
  ConstantRef = Struct.new(:text, :absolute, :crefs, :line, :column, :method)

  # Parses one Ruby file with Prism: requires, definitions, references to constants and calls
  class SourceScanner < Prism::Visitor
    # Methods that load a file
    REQUIRE_METHODS = %i[require require_relative].freeze
    # Methods that call another method by name: `send(:require, path)` is dynamic loading
    SEND_METHODS = %i[send public_send __send__].freeze

    class << self
      # @param path [Pathname, String] Ruby file
      # @return [SourceInfo]
      # @raise [Error] if the file cannot be parsed
      def scan(path)
        path = Pathname.new(path)
        result = Prism.parse_file(path.to_s)
        raise Error, "Syntax error in #{path}: #{result.errors.map(&:message).join(', ')}" unless result.success?
        scanner = new(path)
        result.value.accept(scanner)
        scanner.info
      end
    end

    def initialize(path)
      super()
      @path = path
      @requires = []
      @defs = Set.new
      @refs = []
      @calls = {}
      @singleton_methods = Set.new
      @instance_methods = Hash.new { |h, k| h[k] = Set.new }
      # Full names of the enclosing modules and classes (innermost last)
      @cref = []
      @in_singleton = false
      @in_def = 0
      @conditional = 0
    end

    # @return [SourceInfo]
    def info
      SourceInfo.new(path: @path, requires: @requires, defs: @defs, refs: @refs, calls: @calls, singleton_methods: @singleton_methods,
        instance_methods: @instance_methods, source: @path.read)
    end

    def visit_class_node(node)
      visit(node.superclass) if node.superclass
      scope(node.constant_path) { visit(node.body) if node.body }
    end

    def visit_module_node(node)
      scope(node.constant_path) { visit(node.body) if node.body }
    end

    def visit_singleton_class_node(node)
      if node.expression.is_a?(Prism::SelfNode)
        saved = @in_singleton
        @in_singleton = true
        visit(node.body) if node.body
        @in_singleton = saved
      else
        super
      end
    end

    def visit_def_node(node)
      @in_def += 1
      track_def(node)
      super
    ensure
      @in_def -= 1
    end

    def visit_constant_write_node(node)
      @defs << qualify([node.name.to_s], false)
      visit(node.value)
    end

    def visit_constant_or_write_node(node)
      @defs << qualify([node.name.to_s], false)
      visit(node.value)
    end

    def visit_constant_path_write_node(node)
      parts = const_parts(node.target)
      @defs << qualify(parts[1], parts[0]) if parts
      visit(node.value)
    end

    def visit_constant_read_node(node)
      add_ref(node, nil)
    end

    def visit_constant_path_node(node)
      add_ref(node, nil) || super
    end

    # `defined?(Foo)` is a test, not a use
    def visit_defined_node(_node)
      nil
    end

    # Constructs under which a require can express an optional feature
    def visit_if_node(node) = conditional { super }

    def visit_unless_node(node) = conditional { super }

    def visit_rescue_modifier_node(node) = conditional { super }

    def visit_begin_node(node)
      node.rescue_clause.nil? ? super : conditional { super }
    end

    def visit_call_node(node)
      @calls[node.name] ||= [node.location.start_line, node.location.start_column + 1]
      receiver = node.receiver
      if receiver.nil? && REQUIRE_METHODS.include?(node.name)
        # A call with a receiver (`obj.require`) is not Kernel#require
        add_require(node, node.name, single_string(node))
        super unless single_string(node)
      elsif receiver.nil? && SEND_METHODS.include?(node.name) && sends_require?(node)
        add_require(node, node.arguments.arguments.first.unescaped.to_sym, nil)
        super
      elsif receiver && const_node?(receiver) && add_ref(receiver, node.name)
        visit(node.arguments) if node.arguments
        visit(node.block) if node.block
      else
        super
      end
    end

    private

    def conditional
      @conditional += 1
      yield
    ensure
      @conditional -= 1
    end

    def add_require(node, kind, path)
      @requires.push(RequireDirective.new(file: @path.to_s, kind: kind, path: path, line: node.location.start_line, column: node.location.start_column + 1,
        conditional: @conditional.positive?, lazy: @in_def.positive?))
    end

    def sends_require?(node)
      first = node.arguments&.arguments&.first
      first.is_a?(Prism::SymbolNode) && REQUIRE_METHODS.include?(first.unescaped.to_sym)
    end

    def track_def(node)
      if node.receiver.is_a?(Prism::SelfNode) || @in_singleton
        @singleton_methods << "#{@cref.last}.#{node.name}" if @cref.last
      elsif @cref.last
        @instance_methods[@cref.last] << node.name
      end
    end

    # @return [String, nil] The string argument, if the only argument is a literal string
    def single_string(node)
      args = node.arguments&.arguments
      args.first.unescaped if args&.size.eql?(1) && args.first.is_a?(Prism::StringNode)
    end

    def const_node?(node)
      node.is_a?(Prism::ConstantReadNode) || node.is_a?(Prism::ConstantPathNode)
    end

    # @return [Array(Boolean, Array<String>), nil] absolute?, names; nil if not a path of constants
    def const_parts(node)
      case node
      when Prism::ConstantReadNode
        [false, [node.name.to_s]]
      when Prism::ConstantPathNode
        return [true, [node.name.to_s]] if node.parent.nil?
        parent = const_parts(node.parent)
        parent && [parent[0], parent[1] + [node.name.to_s]]
      end
    end

    # @return [String] Full name of a constant in the current scope
    def qualify(names, absolute)
      (absolute ? names : [@cref.last, *names]).compact.join('::')
    end

    # Class or module definition: the name is defined, the body is in its scope
    def scope(path_node)
      parts = const_parts(path_node)
      return yield if parts.nil?
      name = qualify(parts[1], parts[0])
      @defs << name
      @cref.push(name)
      yield
    ensure
      @cref.pop unless parts.nil?
    end

    # @return [Boolean] true if the node is a path of constants and a reference was recorded
    def add_ref(node, method)
      parts = const_parts(node)
      return false if parts.nil?
      @refs.push(ConstantRef.new(parts[1].join('::'), parts[0], @cref.dup, node.location.start_line, node.location.start_column + 1, method))
      true
    end
  end
end

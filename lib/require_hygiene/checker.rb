# frozen_string_literal: true

require 'pathname'
require_relative 'diagnostic'
require_relative 'runtime_snapshot'
require_relative 'source_scanner'

module RequireHygiene
  # Missing, unused and duplicate requires of Ruby files, from the AST (Prism) and from what libraries provide at runtime.
  #
  # What a `require` provides:
  #
  # - a facade (a file that only requires other files, like an aggregate entry point): what the files it requires provide, recursively
  # - a file of the load paths: the constants it defines (class, module, constant assignment), its singleton methods
  #   (`MyGem.assert`) and the methods it adds to core classes (`Hash#deep_merge`)
  # - another library (standard library or gem): the constants that appear when it is loaded, found by loading it in a new process
  #
  # Limits: a `require` is judged only on what it provides. A `require` that provides nothing detectable (side effect, global
  # variables, methods of core classes) is never reported as unused. A constant that cannot be resolved (dynamic, inherited) is ignored.
  # `extra_provides` and `usage_patterns` declare exceptions.
  class Checker
    # Source patterns that show the use of a library that provides no constant. In the configuration: `allow.usage_patterns`
    USAGE_PATTERNS = {
      'English'    => /\$(?:CHILD_STATUS|ERROR_INFO|ERROR_POSITION|INPUT_RECORD_SEPARATOR|PROCESS_ID|PID|PROGRAM_NAME|LAST_MATCH_INFO|FIELD_SEPARATOR|OUTPUT_FIELD_SEPARATOR|RS|ORS|FS|OFS|NR|NF)\b/,
      'pp'         => /\bpp[ (]|\.pretty_inspect\b|\.pretty_print\b/,
      # Methods added to core classes
      'time'       => /\b(?:Time\.(?:parse|iso8601|strptime|rfc2822|httpdate|xmlschema)|\.(?:iso8601|xmlschema|httpdate|rfc2822))\b/,
      'yaml'       => /\.to_yaml\b/,
      'json'       => /\.(?:to_json|as_json)\b/,
      'tmpdir'     => /\bDir\.(?:mktmpdir|tmpdir)\b/,
      'io/console' => /\.(?:noecho|winsize|raw|getch|echo=|console|getpass)\b|\bIO\.console\b/
    }.freeze

    # Libraries of Ruby (default and bundled gems) that are always loaded, in addition to the ones the checked files require:
    # a constant of one of them (`Date`) is then reported as missing even when no file requires its library, and whatever
    # other libraries happen to be loaded (`psych` loads `date` since psych 5.2, not before).
    # A library that cannot be loaded (not installed with this Ruby) is ignored.
    STANDARD_LIBRARIES = %w[
      abbrev base64 benchmark bigdecimal cgi coverage csv date delegate digest English erb etc fcntl fiddle fileutils find
      forwardable getoptlong io/console io/nonblock io/wait ipaddr json logger matrix monitor mutex_m net/ftp net/http net/imap
      net/pop net/protocol net/smtp nkf objspace observer open-uri open3 openssl optparse ostruct pathname pp prettyprint prime
      pstore psych racc rbconfig readline reline resolv rinda/rinda ripper securerandom set shellwords singleton socket stringio
      strscan syslog tempfile time timeout tmpdir tsort uri weakref yaml zlib
    ].freeze

    # Libraries that are a documented entry point of another one, and so provide its constants: `require 'yaml'` provides `Psych`
    FACADES = {
      'yaml'      => %w[psych],
      'net/https' => %w[net/http]
    }.freeze

    # @param load_paths     [Array<String>] Folders in the load path, where `require 'a/b'` is `a/b.rb`
    # @param files          [Array<String>] Files to check
    # @param extra_files    [Array<String>] Other files that provide constants but are not checked
    # @param root           [String]        Folder from which file names are displayed
    # @param extra_provides [Hash{String => Array<String>}] Constants provided by a require, in addition to what it defines or loads
    # @param usage_patterns [Hash{String => Regexp}]        Source patterns that show the use of a library, in addition to {USAGE_PATTERNS}
    def initialize(load_paths:, files:, extra_files: [], root: Dir.pwd, extra_provides: {}, usage_patterns: {})
      @load_paths = load_paths.map { |path| Pathname.new(path).expand_path }
      @root = Pathname.new(root).expand_path
      @checked = files.map { |file| Pathname.new(file).expand_path }.uniq.sort
      @extra_provides = extra_provides
      @usage_patterns = USAGE_PATTERNS.merge(usage_patterns)
      indexed = (@load_paths.flat_map { |path| path.glob('**/*.rb') } + @checked + extra_files.map { |file| Pathname.new(file).expand_path }).uniq
      @infos = indexed.to_h { |path| [path, SourceScanner.scan(path)] }
      @core = RuntimeSnapshot.core_constants.to_set
      index_external
      index_internal
    end

    # @return [Array<SourceInfo>] The files checked
    def checked_infos
      @checked.map { |path| @infos[path] }
    end

    # @return [Array<Diagnostic>] Problems found in the checked files
    def check
      @checked.flat_map { |path| check_file(@infos[path]) }
    end

    private

    def display(path)
      path.relative_path_from(@root).to_s
    end

    # @return [Pathname, nil] File of the load paths for a require
    def internal_file(info, req)
      return unless req.static?
      candidates = req.relative? ? [info.path.dirname / "#{req.path}.rb"] : @load_paths.map { |path| path / "#{req.path}.rb" }
      candidates.map(&:cleanpath).find { |candidate| @infos.key?(candidate) }
    end

    # @return [Pathname, nil] File of the load paths that `require name` loads
    def internal_path(name)
      @load_paths.map { |path| (path / "#{name}.rb").cleanpath }.find { |candidate| @infos.key?(candidate) }
    end

    def internal_name?(name)
      @load_paths.any? { |path| @infos.key?((path / "#{name}.rb").cleanpath) }
    end

    def index_internal
      @defined_by = Hash.new { |h, k| h[k] = Set.new }
      @singleton_by = Hash.new { |h, k| h[k] = Set.new }
      @extension_by = Hash.new { |h, k| h[k] = Set.new }
      @infos.each_value do |info|
        # Reopened classes of core or libraries (`Hash`, `Logger`) are not provided by the file that extends them
        info.defs.each { |name| @defined_by[name] << info.path unless @core.include?(name) || @external_by_const.key?(name) }
        info.singleton_methods.each { |name| @singleton_by[name] << info.path }
        info.instance_methods.each do |scope, methods|
          methods.each { |name| @extension_by[name] << info.path } if @core.include?(scope)
        end
      end
    end

    def index_external
      names = @checked.flat_map { |path| @infos[path].requires.select { |r| r.static? && !r.relative? }.map(&:path) }.uniq.reject { |n| internal_name?(n) }
      names = (names + STANDARD_LIBRARIES + FACADES.values.flatten).uniq.reject { |n| internal_name?(n) }
      # name => result, libraries that cannot be loaded (optional gems that are not installed) are ignored.
      # The constant `VERSION` is not a use of the library
      loaded = RuntimeSnapshot.many(names).compact
      # A library does not own the constants of the libraries it loads itself: `uri` loads `ipaddr`, but `IPAddr` is not provided by `uri`.
      # Using it through `uri` is depending on a sub-dependency, that can change with the version of the library (`psych` loads
      # `date` since psych 5.2). A constant is owned by the library unless another known library, or one of its files
      # (`digest/sha2` of `digest`), was being required when it appeared. Except for a facade, that provides the library it is
      # the entry point of. The constant `VERSION` is not a use of the library.
      @external = loaded.to_h do |name, result|
        others = loaded.keys.reject { |other| other.eql?(name) || FACADES.fetch(name, []).include?(other) }
        foreign = ->(req) { others.any? { |other| req.eql?(other) || req.start_with?("#{other}/") } }
        owned = result.constants.reject do |c|
          c.end_with?('::VERSION') || result.owners.fetch(c, []).drop(1).any?(&foreign)
        end
        [name, owned.to_set]
      end
      @external_by_const = Hash.new { |h, k| h[k] = Set.new }
      @external.each { |name, consts| consts.each { |c| @external_by_const[c] << name } }
    end

    # @return [Array(Symbol, String, Set), nil] kind (`:internal`, `:external`, `:core`), constant, providers; nil if unresolved
    def resolve(ref)
      candidates = ref.absolute ? [ref.text] : ref.crefs.reverse.map { |c| "#{c}::#{ref.text}" } + [ref.text]
      candidates.each do |name|
        if @defined_by.key?(name)
          providers = @defined_by[name]
          by_method = ref.method && @singleton_by["#{name}.#{ref.method}"]
          return [:internal, name, by_method.nil? || by_method.empty? ? providers : by_method]
        end
        # Constant not listed (autoload, e.g. `Digest::SHA256`): the one that contains it
        parts = name.split('::')
        parts.size.downto(1) do |size|
          prefix = parts.first(size).join('::')
          return [:core, prefix, nil] if @core.include?(prefix)
          return [:external, prefix, @external_by_const[prefix]] if @external_by_const.key?(prefix)
        end
      end
      nil
    end

    def check_file(info)
      findings = []
      internal = {}
      external = Set.new
      # Requires at the top of the file: a require in a method (optional gem, loaded when needed) repeats only these
      top = Set.new
      info.requires.select(&:static?).each do |req|
        key = [req.path, req.relative?]
        findings.push(duplicate(info, req)) if top.include?(key)
        top << key unless req.lazy?
        (file = internal_file(info, req)) ? internal[file] = req : external << req.path
      end
      # Files that are available through the requires of the file
      available = internal.keys.flat_map { |file| provided_files(file).to_a }.to_set
      extra = info.requires.select(&:static?).flat_map do |r|
        canonical = (f = internal_file(info, r)) ? require_name(f) : r.path
        constants = @extra_provides.fetch(canonical) { @extra_provides.fetch(r.path, []) }
        constants.map { |c| [c, f || r.path] }
      end.to_h
      used_internal = Set.new
      used_external = Set.new
      missing = {}
      info.refs.each do |ref|
        kind, name, providers = resolve(ref)
        if extra.key?(ref.text) || extra.key?(name)
          provider = extra.fetch(ref.text) { extra.fetch(name) }
          provider.is_a?(Pathname) ? used_internal << provider : used_external << provider
          next
        end
        case kind
        when :internal
          used_internal.merge(providers)
          unless providers.include?(info.path) || providers.intersect?(available)
            missing[name] ||= [ref.line, ref.column, providers.map { |p| require_name(p) }, :high]
          end
        when :external
          used_external.merge(providers)
          missing[name] ||= [ref.line, ref.column, providers.to_a, :medium] unless providers.intersect?(external)
        end
      end
      # Methods added to core classes (a method name is not proof of use: the same name in another class is possible)
      info.calls.each do |call, (line, column)|
        providers = @extension_by[call] if @extension_by.key?(call)
        next if providers.nil?
        used_internal.merge(providers)
        next if providers.include?(info.path) || providers.intersect?(available)
        missing["#{call} (method)"] ||= [line, column, providers.map { |p| require_name(p) }, :low]
      end
      missing.each { |name, (line, column, providers, confidence)| findings.push(missing_finding(info, name, line, column, providers, confidence)) }
      # The requires of a facade are its purpose
      internal.each do |file, req|
        next if info.facade?
        target = @infos[file]
        next if file.eql?(info.path) || !(target.facade? || provides?(target)) || provided_files(file).intersect?(used_internal)
        findings.push(unused(info, req, 'nothing provided by this file is used', :medium))
      end
      info.requires.each do |req|
        next if info.facade? || !req.static? || internal_file(info, req) || req.relative?
        next if used_external.include?(req.path)
        pattern = @usage_patterns[req.path]
        next if pattern&.match?(info.source)
        # Cannot be loaded, or no constant of its own: side effect, cannot be checked
        consts = @external[req.path]
        next if consts.nil? || consts.empty? && pattern.nil?
        findings.push(unused(info, req, 'none of its constants is used', :medium))
      end
      findings.sort_by { |finding| [finding.line, finding.column] }
    end

    def require_name(path)
      @load_paths.filter_map { |lib| path.relative_path_from(lib).sub_ext('').to_s if path.to_s.start_with?("#{lib}/") }.first || display(path)
    end

    def missing_finding(info, name, line, column, providers, confidence)
      Diagnostic.new(
        rule:       'missing_require',
        file:       display(info.path),
        line:       line,
        column:     column,
        confidence: confidence.to_s,
        severity:   'warning',
        message:    "#{name} is used, but not provided by a require of this file: add require '#{providers.first}'" \
          "#{" (or one of: #{providers.join(', ')})" if providers.size > 1}",
        subject:    {constant: name},
        evidence:   {candidates: providers, direct_requires: info.requires.select(&:static?).map(&:path)}
      )
    end

    def unused(info, req, reason, confidence)
      Diagnostic.new(
        rule:       'unused_require',
        file:       display(info.path),
        line:       req.line,
        column:     req.column,
        confidence: confidence.to_s,
        severity:   'info',
        message:    "require '#{req.path}': #{reason}",
        subject:    {require: req.path, kind: req.kind.to_s},
        evidence:   {conditional: req.conditional?, lazy: req.lazy?}
      )
    end

    def duplicate(info, req)
      Diagnostic.new(
        rule:       'duplicate_require',
        file:       display(info.path),
        line:       req.line,
        column:     req.column,
        confidence: 'high',
        severity:   'warning',
        message:    "require '#{req.path}' is already there",
        subject:    {require: req.path, kind: req.kind.to_s},
        evidence:   {}
      )
    end

    # @return [Set<Pathname>] The file, and the files it provides when it is a facade (recursively)
    def provided_files(file, acc = Set.new)
      return acc unless acc.add?(file)
      info = @infos[file]
      info.requires.each { |req| (target = internal_file(info, req)) && provided_files(target, acc) } if info.facade?
      acc
    end

    # @return [Boolean] true if the file provides something that can be detected as used
    def provides?(info)
      info.defs.any? { |name| !@core.include?(name.split('::').first) } ||
        !info.singleton_methods.empty? ||
        info.instance_methods.any? { |scope, _| @core.include?(scope) }
    end
  end
end

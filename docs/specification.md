# Specification: Ruby `require` Hygiene Analyzer

<!-- gfm2pdf
common:
  metadata:
    subtitle: "Specification"
    author: "Laurent Martin"
-->

| | |
| --- | --- |
| **Gem and command name** | `require_hygiene` (name free on RubyGems when checked on 14 November 2026) |
| **Status** | Prototype specification, revised after the Phase 0 spike (see [Research log](research_log.md)) |
| **Date** | 14 November 2026 |
| **Language** | English |
| **Initial target** | Ruby gems, with `lib/` as the primary analysis scope |
| **Primary deliverable** | A gem: a reusable analysis library (`RequireHygiene`) and a command line tool (`bin/require_hygiene`, built with Thor) |
| **Potential integration** | RuboCop extension, after the analysis engine is validated |

Related documents: [Manual](manual.md), [Development guide](development.md), [Research log](research_log.md).

## Executive summary

Ruby developers need a reliable way to answer two related questions at
the **source-file level**:

1.  **Is this file missing a `require`?**\
    Does it reference a constant or other statically identifiable API
    that is only available because another file happened to be loaded
    earlier?

2.  **Does this file contain an unnecessary `require`?**\
    Does it load a file or library whose declarations are not used by
    this file, and which does not appear to be needed for a side effect?

Existing tools cover parts of this problem, but no mature, widely
adopted solution is known to provide both analyses at file level with
useful explanations and conservative treatment of Ruby's dynamic
behavior.

The tool combines:

- Ruby AST parsing with **Prism**;
- constant-reference resolution against what each file and each library
  actually **provides**: constants defined in the project (AST), and
  constants a library adds when loaded in a new Ruby process (runtime
  snapshot);
- explicit resolution of `require` and `require_relative` paths;
- conservative analysis of side effects and dynamic loading;
- diagnostics that explain the evidence and confidence behind each
  finding;
- runtime isolation checks as a complementary validation mechanism;
- **Shopify Rubydex** as an optional, replaceable semantic backend, for the
  cases the first approach cannot resolve (inheritance, included modules).

The deliverable is a Ruby gem with two entry points that share one engine: a
library API for other tools (see [Packaging, library API and CLI](#packaging-library-api-and-cli)) and a
command line tool.

The first engine (see [Baseline implementation](#baseline-implementation)) is a working
implementation of the missing, unused and duplicate-require rules. The specification below is the target it evolves to.

The tool must not promise perfect static analysis. Its design goal is to
produce **useful, explainable findings with low false-positive rates**,
not to make unsafe automatic changes.

## Baseline implementation

The first engine is a library (`SourceScanner`, `RuntimeSnapshot`, `Checker`, `IsolationCheck`, `Baseline`) used by
the command line tool.

### How it works

1. **Scan** each Ruby file with Prism (`SourceScanner`): `require`
   directives (static, dynamic, conditional, lazy in a method), constants
   defined (class, module, assignment), constants referenced with their
   lexical nesting, singleton methods (`Foo.bar`), and methods added to
   core classes (`Hash#deep_merge`).
2. **Index what each `require` provides**:
   - a file of the load paths provides the constants and methods it defines;
   - a **facade** (a file that only requires other files, such as an
     aggregate entry point) provides what the files it requires provide,
     recursively;
   - another library provides the constants that appear when it is loaded
     in a new Ruby process (`RuntimeSnapshot`). A library does not own the
     constants of the libraries it loads itself (`uri` loads `ipaddr`, but
     `IPAddr` is not provided by `uri`).
3. **Resolve** each reference through the lexical nesting, as Ruby does, to a
   provider: project file, library, or Ruby core.
4. **Report** (`Checker`):
   - `missing_require`: a constant is used, and no `require` of this file
     provides it. It works only thanks to another file or to the load order;
   - `unused_require`: nothing the file requires is used;
   - `duplicate_require`: the same `require` twice at the top of the file.
5. **Complementary runtime check** (`IsolationCheck`): load each file alone in
   a new process. A failure caused by a library that is not installed is
   reported as optional, not as an error.

### Conservative rules already in the baseline

- A `require` that provides nothing detectable (side effect, global
  variables) is never reported as unused.
- `defined?(Foo)` is a test, not a use.
- A constant that cannot be resolved is ignored, never reported.
- A `require` inside a method (optional library loaded when needed) is not a
  duplicate of the one at the top.
- The requires of a facade are its purpose: not reported as unused.
- A `require` of a library without constants is judged by source patterns
  (`English`, `pp`, `json`, ...), extensible with `allow.usage_patterns`.
- `allow.extra_provides` declares what a require provides in addition
  (for example, `using Colors` needs the gem loaded by `my_gem/colors`).

### Baseline file

A large code base cannot fix all findings at once. As with
`.rubocop_todo.yml`, `--write-baseline` records the current findings in
`.require_hygiene_todo.yml`, and only **new** findings are reported afterwards.
An entry has no line number, so it survives code moves. Entries that are
fixed are listed, to be removed.

### Differences with this specification

| Topic | Baseline | Target of the specification |
| --- | --- | --- |
| Constant resolution | Names, lexical nesting, project index | Semantic backend with ancestors (Rubydex), see [Semantic analysis adapter](#semantic-analysis-adapter) |
| Library constants | Snapshot by loading the library, which **executes its code** | Same, plus static metadata where loading is not wanted |
| Transitive availability | Facades only | Explicit direct and transitive policies, with the chain shown |
| Evidence | Message and candidates | Full evidence of the [JSON schema](#json-diagnostic-schema) |
| Conditional requires | Recorded, not yet a separate policy | Separate policy, see [Conditional requires](#conditional-requires) |
| Unused states | Reported, or not | `used`, `likely_unused`, `uncertain`, `unresolved` |
| Confidence | `high` for a project file, `medium` for a library, `low` for a method added to a core class | Full [model](#confidence-and-severity-model) |

## Problem statement

### Missing requires: implicit load-order dependencies

A Ruby source file can appear to work when loaded through the gem's main
entry point while failing when loaded independently.

For example:

``` ruby
# lib/example/client.rb
module Example
  class Client
    def initialize
      @connection = Faraday.new
    end
  end
end
```

If `Faraday` is only available because another file or the gem entry
point loaded it first, `client.rb` has an undeclared dependency. The
file should normally contain the appropriate explicit `require`, unless
the project deliberately relies on another documented loading mechanism.

Such dependencies cause:

-   failures when files are loaded in a different order;
-   brittle tests and application boot sequences;
-   unexpected behavior for users requiring a specific file;
-   difficult-to-diagnose circular or indirect dependencies.

### Unused requires: unnecessary loading

The reverse problem also matters:

``` ruby
require 'json'
require 'set'

class Parser
  # Uses JSON, but nothing from Set.
end
```

An unnecessary `require` can:

-   increase startup time and memory use;
-   obscure the actual dependency surface;
-   create avoidable transitive dependencies;
-   trigger initialization or other side effects;
-   make future maintenance harder.

A dependency-level tool cannot necessarily identify which source file
contains the unnecessary directive. The required granularity is
therefore the individual Ruby file.

### Why this is difficult in Ruby

Ruby's loading and constant systems are dynamic. Static analysis must
account for, or explicitly classify, cases such as:

-   lexical constant lookup and ancestor lookup;
-   included and extended modules;
-   aliases and reopened classes/modules;
-   conditional definitions;
-   `autoload`;
-   dynamic `require` paths;
-   `eval`, `send`, and computed constant names;
-   C extensions and native code;
-   registration and monkey-patching side effects;
-   optional dependencies loaded conditionally;
-   constants provided by the Ruby runtime, standard library, default
    gems, or third-party gems.

A tool that simply searches source text for constant names will not be
sufficiently reliable.

## User need and existing ecosystem evidence

The project should solve a real, currently unmet user need rather than
create another generic linter.

The discussion that led to this specification identified several
relevant signals:

1.  **A long-standing request for require bookkeeping.** A Ruby
    community discussion from 2005 asked for a tool that could identify
    extra `require` statements and related bookkeeping errors. This is
    evidence of a persistent class of need, although the original thread
    and its current accessibility should be verified before using it as
    a formal project reference.

2.  **Limitations reported around `rubocop-require_tools`.** The
    discussion identified real-world cases involving constants supplied
    through included modules and constants guarded by `const_defined?`.
    These cases illustrate how difficult reliable constant resolution
    can be. The referenced issue and pull-request history should be
    checked against the current upstream repository before making public
    claims.

3.  **`degem`'s acknowledged limitations.** The discussion identified an
    issue proposing AST-based analysis instead of
    regular-expression-based detection, including examples involving
    nested constants and indirect usage. This supports the need for
    syntax- and semantics-aware analysis. `degem` operates primarily at
    bundle/dependency level, which is different from this project's
    file-level goal.

4.  **`lopper`'s cautious handling of Ruby imports.** The discussion
    identified an implementation that reports unused imports while
    warning when runtime require signals make removal uncertain. This is
    consistent with the proposed conservative policy.

These observations are useful product evidence, but they should be
treated as **research leads to verify**, not as immutable statements
about current project status. Before publishing the tool, record the
exact upstream URLs, issue/PR numbers, dates, versions, and current
status.

### Existing tools and their intended role

| Project / technology | Potential role | Limitation or question to validate |
| --- | --- | --- |
| `rubocop-require_tools` | Existing RuboCop checks, especially missing-require detection; possible compatibility reference | Verify current maintenance, supported RuboCop/Ruby versions, and actual resolution behavior |
| Shopify `rubydex` | Candidate semantic index, dependency graph, constant resolution, and reference tracking | Experimental status and API suitability must be validated; do not couple the analyzer directly to undocumented internals |
| Ruby `Prism` | Parser and AST for require directives, source locations, and syntax-level evidence | AST alone does not resolve runtime constant ownership |
| `degem` | Bundle-level unused-gem analysis; useful comparison | Not a replacement for file-level require analysis |
| `lopper` | Prior art for unused-import reporting and uncertainty around dynamic imports | Validate Ruby-specific precision and whether its model fits Ruby gem semantics |
| `rigor` | Possible reference for advanced constant/reachability analysis | Full type inference is not required for the first prototype |
| `debride`, `leftovers` | General dead-code analysis and possible complementary tooling | They do not directly solve require attribution |

**Positioning:** The project should not begin as a fork or a presumed
incremental release of `rubocop-require_tools`. It should first be a
focused analysis engine with a stable internal model. A RuboCop
extension can later expose that engine through familiar diagnostics.
Reuse existing code where licensing, maintenance, and architecture make
that practical.

## Goals

The prototype must:

1.  Analyze Ruby source files individually, primarily under a gem's
    `lib/` directory.
2.  Parse source reliably and retain exact source locations.
3.  Collect static `require` and `require_relative` calls.
4.  Resolve static require paths to source files where possible.
5.  Identify statically resolvable constant references and their
    declarations.
6.  Detect likely missing direct requires.
7.  Detect likely unused requires.
8.  Distinguish high-confidence findings from ambiguous cases.
9.  Explain each finding with evidence: reference, declaration, file
    path, and loading relationship.
10. Produce human-readable and machine-readable output.
11. Be usable locally and in CI.
12. Provide a path to later RuboCop integration without making RuboCop a
    dependency of the analysis core.

### Quality goals

The prototype should optimize for:

-   **Precision before recall:** avoid noisy diagnostics that developers
    will learn to ignore.
-   **Explainability:** every diagnostic should show why it was emitted.
-   **Conservative behavior:** uncertainty must be visible, not silently
    converted into a definite finding.
-   **Reproducibility:** the same source, Ruby version, configuration,
    and dependency environment should produce the same result.
-   **Replaceable analysis backends:** the core must not depend on one
    experimental parser/indexer API.
-   **Practical performance:** a normal gem should be analyzable in a
    reasonable time, with indexing performed once per run.

## Non-goals for the prototype

The first prototype will not:

-   automatically add or remove `require` statements;
-   guarantee correctness for arbitrary dynamic Ruby;
-   perform full Ruby type inference;
-   model every possible runtime effect of loading a file;
-   analyze Rails application autoloading or Zeitwerk conventions as its
    primary use case;
-   replace unit tests or runtime loading tests;
-   determine whether every declared gem dependency in a Gemfile or
    gemspec is necessary;
-   analyze the internal require hygiene of all third-party
    dependencies;
-   enforce a single project-wide loading style.

The initial target is conventional Ruby gems using explicit loading from
`lib/`. Other layouts may be supported later.

## Core concepts and terminology

The implementation should use precise terms:

-   **Source file:** a Ruby file being analyzed.
-   **Require directive:** a statically recognized call to `require` or
    `require_relative`.
-   **Required file:** the file resolved from a require directive.
-   **Constant reference:** a statically recognized reference to a Ruby
    constant.
-   **Constant declaration:** a statically recognized definition or
    assignment that introduces a constant.
-   **Direct require:** a require directive written in the file being
    analyzed.
-   **Transitive availability:** a file may become loaded through
    another file's require chain.
-   **Side-effect require:** a require whose purpose may be
    initialization, registration, patching, or native extension loading
    rather than use of a newly declared constant.
-   **Unresolved require:** a require whose target cannot be mapped to a
    source file statically.
-   **Dynamic loading:** loading performed through computed paths or
    indirect mechanisms that cannot be resolved confidently from source.

A key distinction: **a constant being available at runtime is not proof
that the current file explicitly declares its dependency.** The analyzer
should report directness and transitive availability separately.

## Proposed architecture

Use a layered design so that parsing, semantic indexing, require
resolution, analysis policy, and reporting can evolve independently.

``` text
                  +--------------------------+
                  | CLI / future RuboCop API|
                  +------------+-------------+
                               |
                  +------------v-------------+
                  | Analysis orchestration   |
                  +------------+-------------+
                               |
            +------------------+------------------+
            |                  |                  |
+-----------v------+ +---------v---------+ +------v-----------+
| Source discovery | | Require extraction| | Semantic analysis|
| and configuration| | and path resolver | | adapter          |
+-----------+------+ +---------+---------+ +------+-----------+
            |                  |                  |
            +------------------+------------------+
                               |
                  +------------v-------------+
                  | Per-file analysis model  |
                  | and diagnostic engine    |
                  +------------+-------------+
                               |
                  +------------v-------------+
                  | Text / JSON / CI output  |
                  +--------------------------+
```

### Parser layer

Use Prism as the preferred parser if its version and Ruby syntax
coverage meet the project's supported Ruby range.

Responsibilities:

-   parse each source file;
-   identify `require` and `require_relative` calls;
-   collect constant reads, writes, and declarations where useful;
-   retain source locations and lexical nesting;
-   identify conditional and dynamic constructs;
-   report syntax errors without crashing the whole run.

Do not build a second Ruby parser. Keep parser-specific node handling
behind a small adapter.

### Semantic analysis adapter

Evaluate Rubydex first because the discussion identified it as a
promising source of:

-   workspace indexing;
-   constant declarations and references;
-   constant resolution in lexical context;
-   ancestor-aware resolution;
-   require-path resolution or dependency graph information.

The Phase 0 spike (see [Research log](research_log.md)) verified, with
Rubydex 0.4.4 (MIT license, Ruby `>= 3.2`, precompiled native gems), that
`Rubydex::Graph#index_all`, `#resolve`, `#constant_references` and
`#resolve_require_path` exist and behave as described below. These are
still not contractual interfaces for this project: Rubydex is
experimental, and the version is pinned to a minor range in the gemspec.

Observed behavior that the adapter must handle:

- **Positions are zero-based** (line and column). Normalized records use
  one-based lines and columns.
- A reference is either a `ResolvedConstantReference` (with a
  `declaration`) or an `UnresolvedConstantReference` (with a `name`).
- **Only indexed files can resolve a constant.** A constant from a gem
  or from the standard library that was not indexed (`Faraday`, `JSON`)
  is unresolved, which is exactly the information the analyzer needs,
  but it must be reported as "no declaration found in the indexed
  scope", not as "does not exist".
- Core classes (`String`) are unresolved unless the RBS core
  definitions are indexed. When they are, the declaration is in a
  `.rbs` file, which the adapter must classify as runtime-provided and
  never as a file to require.
- One source reference can produce several records at the same
  location. For `A.new` in `Ex::B`, the graph returned `Ex::A` and a
  record named `Ex::A::<A>`, apparently the singleton class of `Ex::A`.
  Records with a name in `<...>` must be normalized away, and records
  at the same location must be merged.
- `resolve_require_path(path, load_paths)` returns a document (`uri`) or
  `nil`. A `nil` for `json` only means that the standard library is not
  indexed or not on the given load paths.
- `Graph#diagnostics` carries rules such as `dynamic_constant_reference`
  and `parse_error`, usable as uncertainty evidence.

Define a small internal interface, for example:

``` ruby
class SemanticIndex
  def index(files:, load_paths:, dependencies:)
    # Build the semantic model.
  end

  def references_for(file)
    # Return resolved and unresolved constant references for this file.
  end

  def declarations_for(file)
    # Return declarations originating in this file.
  end

  def resolve_constant(reference)
    # Return declaration candidates and resolution evidence.
  end
end
```

The actual implementation may wrap Rubydex, Prism plus additional
indexing, or another backend. The analyzer should consume normalized
records rather than Rubydex-specific objects.

### Source and dependency scope

For a gem analysis run, the initial indexing scope should be:

1.  all Ruby files under the target gem's `lib/`;
2.  the gem's own load paths;
3.  installed runtime dependencies needed to resolve external constant
    references;
4.  selected standard-library and default-gem metadata.

Only the target gem's own files are subject to require-hygiene
diagnostics by default. Dependency source may be indexed to resolve
declarations, but should not itself be linted unless explicitly
requested.

Development dependencies should not be treated as runtime-provided APIs
unless configuration says otherwise.

## Require extraction and path resolution

### Supported static forms

Recognize at least:

``` ruby
require 'json'
require "my_gem/client"
require_relative 'client'
require_relative '../support/helpers'
```

Also recognize equivalent calls where the AST confirms a normal method
call with a literal string argument. Do not assume every method named
`require` is necessarily `Kernel#require`; retain receiver and
call-context information.

### Conditional requires

Record whether a require is nested under constructs such as:

``` ruby
if defined?(SomeOptionalGem)
  require 'some_optional_gem'
end
```

or:

``` ruby
begin
  require 'optional_backend'
rescue LoadError
  # optional feature unavailable
end
```

Conditional requires may intentionally express optional features. They
must not be flattened into unconditional loading facts. Mark them as
conditional and apply a separate policy.

### Dynamic requires

Examples:

``` ruby
require adapter_name
require "adapters/#{name}"
send(:require, path)
```

The first prototype should record these as dynamic/unresolved loading
signals. It must not invent a target path.

### Path resolution rules

For `require_relative`, resolve relative to the directory of the source
file, following Ruby's extension and file-resolution behavior as closely
as practical.

For `require`, resolve against the effective `$LOAD_PATH` for the
analysis environment, including the target gem's `lib/` and relevant
installed dependency paths.

The resolver must:

-   distinguish project files from dependency files;
-   account for `.rb` and supported native extension candidates;
-   preserve the original require string;
-   record all candidates if resolution is ambiguous;
-   distinguish not-found from unsupported/dynamic;
-   avoid assuming that a file with a matching basename is the required
    file.

The runtime environment used for resolution must be recorded in the
report (Ruby version, load paths, Bundler context).

## Missing-require analysis

### Intended rule

A file should explicitly load the source that provides the API it uses,
unless the project has a documented exception or the API is guaranteed
by the runtime environment.

The rule is not simply "the defining file must be the target of a direct
require." A required file may itself load other files, and a public
entry point may intentionally expose a supported aggregate API. The
analyzer must model these relationships and report the distinction
between direct and transitive availability.

### Initial algorithm

For each source file `F`:

1.  Collect constant references in `F`.
2.  Resolve each reference to one or more declaration candidates using
    the semantic backend.
3.  Exclude known language-level constants and configured
    runtime-provided constants.
4.  Determine the source file containing the resolved declaration.
5.  Determine whether that source file is:
    -   directly required by `F`;
    -   reachable through a static require chain starting at `F`;
    -   available only because of an external/runtime mechanism;
    -   unresolved.
6.  Emit a finding only when the evidence supports a missing direct
    dependency or a likely implicit load-order dependency.

### Direct versus transitive policy

The tool should support at least two policies:

-   **Self-contained policy (recommended default):** a file should
    directly require the file that defines the API it references, unless
    an explicit public aggregate/entry-point rule says otherwise.
-   **Transitive-allowed policy:** a file is considered satisfied if its
    declaration is reachable through the static require closure.

Even in transitive-allowed mode, the analyzer may report a configurable
advisory when the dependency is only transitively available. This makes
the trade-off explicit instead of embedding it in an ambiguous rule.

### Avoiding false positives

Do not report a missing require when:

-   the constant is defined in the same file;
-   the constant is a Ruby language/core constant available by default;
-   the project explicitly configures the constant as externally
    provided;
-   the reference is unresolved or ambiguous and there is insufficient
    evidence;
-   the relevant API is intentionally supplied by an agreed loading
    convention.

For standard-library and default-gem constants, use version-aware
metadata where possible. Do not rely on a simplistic global list:
availability and packaging can vary by Ruby version and installation.

### Diagnostic evidence

A missing-require diagnostic should include:

-   source file and line/column;
-   referenced constant;
-   resolved declaration and defining file;
-   direct requires found in the source file;
-   whether a transitive path exists;
-   resolution confidence;
-   a suggested require path only when the path is unambiguous.

Example:

``` text
lib/example/client.rb:8:14: missing-require (likely)
  `Faraday` resolves to .../faraday.rb
  No direct require in this file provides this declaration.
  It is currently reachable through:
    lib/example.rb -> lib/example/http.rb -> faraday
  Consider adding the appropriate direct require, or configure this
  dependency as intentionally provided by the aggregate entry point.
```

## Unused-require analysis

### Fundamental limitation

A require may be necessary even when the requiring file does not
reference any new constant from the loaded file.

Examples include:

-   loading a native extension that modifies an existing class;
-   registering an adapter, serializer, driver, or plugin;
-   monkey-patching a class or module;
-   installing callbacks or hooks;
-   registering MIME types or handlers;
-   loading code whose purpose is to execute initialization.

Therefore:

> Absence of a statically detected constant reference is not proof that
> a require is safe to remove.

The tool must not automatically remove requires in the prototype.

### Initial algorithm

For each require directive `r` in source file `F`, resolving to file
`G`:

1.  Collect declarations originating in `G`.
2.  Collect resolved constant references in `F`.
3.  Determine whether any reference in `F` resolves to a declaration
    originating in `G`.
4.  Inspect whether `G` itself loads other files whose declarations are
    used by `F`.
5.  Inspect `G` for indicators of side effects and dynamic behavior.
6.  Consider conditional loading and native extension behavior.
7.  Classify the directive as used, likely unused, or uncertain.

Do not limit the analysis to only top-level constants if the semantic
backend can identify nested declarations and aliases reliably.

### Side-effect indicators

The first prototype should conservatively identify indicators such as:

-   top-level method calls;
-   assignments to existing constants;
-   `include` or `prepend` into existing classes/modules;
-   `extend` or monkey-patching;
-   registration-like calls;
-   `at_exit`, hooks, callbacks, or global configuration;
-   native extension loading;
-   dynamic require/eval behavior;
-   calls whose implementation cannot be inspected.

These indicators are heuristics, not proof. The report should name the
indicator that caused uncertainty.

### Classification

Use these states:

| State | Meaning | Default behavior |
| --- | --- | --- |
| `used` | A reference in the requiring file resolves to a declaration provided by the required file or its statically loaded closure | No finding |
| `likely_unused` | No relevant usage found and no known ambiguity indicator detected | Informational diagnostic |
| `uncertain` | Side effects, dynamic loading, conditional behavior, unresolved references, native code, or incomplete indexing prevent a safe conclusion | Advisory only |
| `unresolved` | The require target could not be resolved | Report resolution limitation; do not call it unused |

Avoid calling any require "definitively unused" unless a much stronger
proof model is implemented and validated. For the prototype,
`likely_unused` is the strongest removal-oriented classification.

### Required-file closure

A source file may require `G`, while `G` requires `H`, and the requiring
file uses a constant declared in `H`. This is a valid reason for the
require of `G` to be used.

Therefore, unused-require analysis must consider the static require
closure of `G`, not only declarations physically located in `G`.

It must also avoid attributing every transitive dependency to every
requiring file without qualification. Diagnostics should show the actual
chain.

## Confidence and severity model

Keep **confidence** separate from **severity**.

### Confidence

-   `high`: the source and semantic relationships are resolved
    unambiguously.
-   `medium`: the result is supported by static evidence but has known
    limitations.
-   `low`: dynamic behavior, incomplete indexing, or ambiguity
    materially affects the result.

### Suggested default policy

| Finding | Confidence | Default severity |
| --- | --- | --- |
| Missing direct require, resolved declaration, no permitted loading path | High/medium | Warning |
| Dependency only available transitively under self-contained policy | High/medium | Warning or configurable info |
| Likely unused require with resolved target and no detected ambiguity | Medium | Info |
| Possible side-effect require | Low | Info/advisory |
| Dynamic or unresolved require | Low | Info/advisory |
| Syntax or indexing failure | N/A | Error for that file/run, not a fabricated require finding |

The CLI should allow CI thresholds such as `--fail-on missing` or
`--fail-on warning`. Uncertain findings must not fail CI by default.

## Configuration

Provide a small configuration file, for example `.require_hygiene.yml`.

Potential settings:

``` yaml
# Illustrative schema; final names are to be confirmed during implementation.
paths:
  include:
    - lib/**/*.rb
  exclude:
    - lib/**/version.rb

policy:
  missing_requires: self_contained
  report_transitive_dependencies: true
  analyze_conditional_requires: advisory

runtime:
  ruby_version: auto
  use_bundler: true

analysis:
  index_runtime_dependencies: true
  index_development_dependencies: false

allow:
  constants:
    - SomeRuntimeProvidedConstant
  side_effect_requires:
    - my_gem/register_builtin_adapters

output:
  format: text
  minimum_confidence: medium
```

Configuration must not become a way to hide all findings. Diagnostics
suppressed by explicit allowlists should be traceable in verbose output.

## CLI and output contract

The CLI is the primary prototype interface.

Illustrative commands:

``` sh
require_hygiene analyze
require_hygiene analyze lib/
require_hygiene analyze --format json
require_hygiene analyze --fail-on missing
require_hygiene analyze --config .require_hygiene.yml
require_hygiene explain lib/example/client.rb:8
```

The exact command syntax can change, but the CLI should support:

-   target path(s);
-   configuration file;
-   text and JSON output;
-   verbosity;
-   confidence/severity filters;
-   non-zero exit status according to configured CI policy.

### JSON diagnostic schema

Use a versioned schema so CI integrations can depend on it.

Example:

``` json
{
  "schema_version": 1,
  "rule": "missing_require",
  "file": "lib/example/client.rb",
  "location": {
    "start_line": 8,
    "start_column": 14
  },
  "confidence": "high",
  "severity": "warning",
  "subject": {
    "constant": "Faraday",
    "definition_file": "/path/to/faraday.rb"
  },
  "evidence": {
    "direct_requires": [],
    "transitive_path": [],
    "resolution": "resolved"
  },
  "message": "Constant Faraday is referenced without a direct require."
}
```

For unused-require findings, include the original directive, resolved
target, declarations/references considered, side-effect indicators, and
uncertainty reasons.

The JSON output must be stable, documented, and independent of Rubydex's
internal object model.

## Packaging, library API and CLI

### Gem layout

```text
require_hygiene.gemspec
Gemfile
Rakefile, rakelib/        build, test and documentation tasks
bin/require_hygiene       executable, only calls RequireHygiene::CLI
lib/require_hygiene.rb    library entry point (does not load Thor)
lib/require_hygiene/
  version.rb
  errors.rb
  configuration.rb        defaults, .require_hygiene.yml
  diagnostic.rb           normalized finding, JSON schema v1
  report.rb               result of an analysis
  analyzer.rb             orchestration: the public entry point
  source_scanner.rb       Prism scan of one file
  runtime_snapshot.rb     constants a library adds when loaded
  checker.rb              missing, unused and duplicate rules
  isolation_check.rb      each file loaded alone
  baseline.rb             known findings file
  workers.rb              parallel sub-processes
  cli.rb                  Thor command line, loaded by bin/ only
docs/                     specification, manual, development guide
test/                     Minitest suite and fixtures (small projects with deliberate defects)
```

### Rules for the library and the command line

1. **The CLI is a thin adapter.** It parses options, calls the library,
   prints the result, and sets the exit status. No analysis logic.
2. **`require 'require_hygiene'` never loads Thor, prints, or calls
   `exit`.** Other tools (a RuboCop extension, an editor integration, a
   CI script) call the library and receive Ruby objects or JSON.
3. **Errors are exceptions** derived from `RequireHygiene::Error`. Only
   the CLI turns them into a message and an exit status.
4. **The JSON schema is the stable contract**, versioned
   (`schema_version`). Ruby classes of the library can change between
   minor versions before 1.0, the JSON cannot without a schema version
   change.
5. **Backends are replaceable.** Rubydex and Prism objects never appear
   in the public API.

### Public library API

```ruby
require 'require_hygiene'

config = RequireHygiene::Configuration.load('.require_hygiene.yml')
report = RequireHygiene::Analyzer.new(config).analyze(['lib'])

report.diagnostics.each { |d| puts "#{d.file}:#{d.line}: #{d.rule}" }
report.to_h # JSON-ready Hash, schema_version: 1
```

| Object | Role |
| --- | --- |
| `Configuration` | Immutable settings, from defaults, a YAML file and overrides. |
| `Analyzer` | `#analyze(paths)` returns a `Report`, `#source_files(paths)` lists the files, `#load_paths` the load path. |
| `Report` | `files`, `directives`, `diagnostics`, `rules`, `#to_h`. |
| `Diagnostic` | One finding. `#to_h` follows the JSON schema. |
| `Checker` | The rules, for a caller that wants the findings without configuration. |
| `SourceScanner` | `.scan(file)` returns what one file requires, defines and references. |
| `RuntimeSnapshot` | What a library provides, found by loading it. |
| `IsolationCheck` | `.run(files:, load_paths:)` loads each file alone. |
| `Baseline` | Known findings: `.write`, `#partition`. |
| `Error` | Base class of all errors of the gem. |

### Command line (Thor)

| Command | Purpose |
| --- | --- |
| `require_hygiene analyze [PATH...]` | Find missing, unused and duplicate requires. Default paths: `paths.include`. |
| `require_hygiene check-load [PATH...]` | Load each file alone in a new process, see [Runtime isolation checks](#runtime-isolation-checks). |
| `require_hygiene explain FILE:LINE` | Planned: show the full evidence of the findings at a location. |
| `require_hygiene version` | Show the version (also `--version`). |

Options of `analyze`: `--config FILE`, `--format text|json`,
`--fail-on missing|unused|warning|never`, `--min-confidence low|medium|high`,
`--verbose`. Exit status: `0` no failing finding, `1` at least one
finding at or above the `--fail-on` threshold, `2` usage, configuration
or analysis error.

### Dependencies and Ruby versions

| Dependency | Constraint | Reason |
| --- | --- | --- |
| `prism` | `>= 1.0` | Syntax-level extraction of requires. |
| `rubydex` | `>= 0.4.4, < 0.5` | Optional semantic backend, not yet a dependency: experimental, minor range only when added. |
| `thor` | `~> 1.3` | Command line. |

Required Ruby: `>= 3.2`, the minimum of Rubydex. RuboCop is never a
dependency of the gem.

### Documentation build

The Markdown files in `docs/` are written for GitHub and converted to PDF
with [gfm2pdf-toolchain](https://github.com/laurent-martin/gfm2pdf-toolchain)
(environment variable `GFM2PDF_HOME`). `rake doc:pdf` builds the PDFs and
`rake doc:check` checks them in CI mode, see the
[Development guide](development.md).

## Runtime isolation checks

Static analysis should be complemented by an isolation test because it
cannot model every Ruby runtime behavior.

A useful independent check is to load each file in a fresh Ruby process
with the gem's `lib/` directory on the load path:

``` ruby
Dir.glob("lib/**/*.rb").each do |file|
  success = system(
    RbConfig.ruby,
    "-Ilib",
    "-e",
    "require #{File.expand_path(file).inspect}"
  )

  warn "Failed to load #{file}" unless success
end
```

This is a conceptual example, not a complete drop-in test. A production
implementation must consider:

-   the current working directory;
-   the gem's supported Ruby versions;
-   Bundler setup and runtime dependencies;
-   files intentionally not designed to be required directly;
-   environment variables and optional features;
-   process timeouts and captured stderr;
-   platform-specific native extensions.

The tool may eventually provide a command to generate or run these
checks, but the first prototype can document the technique and use it to
validate findings.

Runtime isolation is not a replacement for static analysis: a successful
load may still depend on accidental environment state, and a failed load
may be caused by missing configuration rather than a missing require.

## RuboCop integration

Do not make the first prototype a RuboCop cop.

First build and validate the analysis engine and CLI. Then provide an
optional RuboCop extension with rules such as:

-   `RequireHygiene/MissingRequire`
-   `RequireHygiene/UnusedRequire`

The RuboCop layer should translate engine diagnostics into RuboCop
offenses. It should not reimplement constant resolution or require-path
analysis.

Autocorrection should remain disabled initially:

-   inserting a require may introduce cycles or alter load order;
-   removing a require may remove required side effects;
-   the correct require path may be ambiguous.

The integration must be tested against the supported RuboCop versions
and must not force projects to adopt a new parser configuration
unexpectedly.

## Prototype implementation plan

### Phase 0: Feasibility spike

**Status:** first spike done on 14 November 2026, results in the
[Research log](research_log.md). Remaining: comparison on a real gem
and the unused-require facts (declarations by file, require closure).

**Goal:** Establish whether Rubydex can supply the semantic facts
required by the analyzer.

Tasks:

1.  Select a small representative gem and a deliberately constructed
    fixture gem.
2.  Install and pin a Rubydex version.
3.  Index the target gem's `lib/` files.
4.  Verify how to retrieve:
    -   documents and source paths;
    -   constant declarations;
    -   constant references and source locations;
    -   resolved declaration targets;
    -   lexical nesting and ancestor-aware resolution;
    -   require relationships and path resolution, if available.
5.  Parse the same files with Prism and extract require directives.
6.  Compare results against manually verified examples.
7.  Record unsupported Ruby constructs and API gaps.

**Exit criteria:**

A small executable experiment can print, for one file:

-   all static require directives and resolved paths;
-   all resolved constant references;
-   the source file defining each referenced constant;
-   unresolved or ambiguous references.

If Rubydex cannot provide these facts reliably, evaluate alternatives
before building the analysis layer around it.

### Phase 1: Missing-require prototype

**Status:** done with the [baseline implementation](#baseline-implementation) (Prism, project index, runtime snapshot).
Remaining: the separate direct and transitive policies, and the full evidence.

Tasks:

1.  Implement source discovery and Prism parsing.
2.  Implement the semantic adapter.
3.  Normalize constant references and declarations.
4.  Implement require-path resolution.
5.  Implement direct and transitive loading relationships.
6.  Add core/runtime exclusions and configuration.
7.  Emit text and JSON diagnostics.

**Exit criteria:**

-   Correctly detects intentionally removed requires in fixture cases.
-   Does not report constants defined in the same file.
-   Handles nested namespaces and included modules in tested cases.
-   Explains transitive availability.
-   Produces no unexplained findings in a manually audited sample of a
    real gem.

### Phase 2: Unused-require prototype

**Status:** partly done: facades, usage patterns and the conservative rules of the baseline. Remaining: the four states,
side-effect indicators, and the conditional policy.

Tasks:

1.  Build the static require closure for each directive.
2.  Attribute constant usage to declarations in the closure.
3.  Detect common side-effect indicators.
4.  Identify conditional and dynamic requires.
5.  Implement `used`, `likely_unused`, `uncertain`, and `unresolved`
    states.
6.  Add diagnostic explanations.

**Exit criteria:**

-   Detects deliberately redundant ordinary requires in fixtures.
-   Does not classify known side-effect-only requires as safely
    removable.
-   Recognizes a require as used when the used declaration is loaded
    transitively through it.
-   Clearly explains why a result is uncertain.

### Phase 3: Real-gem validation

**Status:** started: `require_hygiene` analyzes itself without finding. The manual precision review of the findings
is not done.

Use a representative real-world gem as an early validation target, alongside small fixture projects.

Tasks:

1.  Run the analyzer against the gem.
2.  Review every finding manually.
3.  Categorize false positives and false negatives.
4.  Add regression fixtures for each discovered case.
5.  Measure runtime and memory use.
6.  Compare findings with isolated-loading tests.

**Exit criteria:**

A documented precision review exists, with each finding in the sample
categorized as correct, false positive, false negative, or intentionally
unresolved. Do not claim quality based only on the number of findings.

### Phase 4: Packaging and CI

The gem skeleton (gemspec, Gemfile, CLI, documentation build) is created
early, see [Packaging, library API and CLI](#packaging-library-api-and-cli);
this phase finishes it.

Tasks:

1.  Package the engine as a gem.
2.  Provide the CLI executable.
3.  Document supported Ruby versions and known limitations.
4.  Add CI examples and exit-code policy.
5.  Add a configuration schema and sample file.
6.  Pin or constrain experimental backend dependencies.

### Phase 5: Optional RuboCop extension

Only after the engine's diagnostics and JSON contract are stable:

1.  Implement RuboCop cops as a thin adapter.
2.  Add compatibility tests for supported RuboCop versions.
3.  Document configuration and severity mapping.
4.  Keep autocorrection disabled unless a specific correction is proven
    safe.

## Test strategy

A test suite must be designed around semantic edge cases, not just
happy-path examples.

### Fixture categories

**Basic loading**

- direct `require`;
- direct `require_relative`;
- nested directory paths;
- extensionless require paths;
- same-file constant declaration.

**Constant resolution**

- top-level constants;
- nested constants;
- lexical nesting;
- `::` root-qualified references;
- included and prepended modules;
- inherited constants;
- reopened classes/modules;
- aliases and constant assignments;
- multiple candidate declarations.

**Require relationships**

- direct require;
- transitive require;
- multiple paths to the same file;
- circular require relationships;
- unresolved require;
- duplicate requires.

**Dynamic and conditional behavior**

- optional dependency guarded by `defined?`;
- `begin`/`rescue LoadError`;
- computed require path;
- `send(:require, ...)`;
- `autoload`;
- `const_get`;
- `eval`.

**Side effects**

- native extension;
- adapter registration;
- monkey-patching;
- `include`/`prepend` into an existing class;
- top-level method calls;
- global configuration;
- hook/callback registration.

**Runtime environment**

- core constants;
- standard library;
- default gems;
- Bundler runtime dependencies;
- development-only dependencies;
- different supported Ruby versions.

### Regression policy

Every bug found during real-gem validation must become a small isolated
fixture with:

-   source files;
-   expected analysis result;
-   explanation of the semantic rule;
-   supported Ruby version(s).

Do not accept a fix that merely suppresses a diagnostic without
understanding the underlying resolution issue.

### Quality metrics

Track at least:

-   precision of missing-require findings;
-   recall on deliberately injected missing requires;
-   precision of likely-unused findings;
-   proportion of requires classified as uncertain;
-   number of unresolved references;
-   runtime and memory use;
-   stability across supported Ruby versions.

The first quality target should be high precision on the supported
subset, not broad but noisy coverage.

## Risks and open technical questions

### Rubydex maturity and API stability

The discussion describes Rubydex as experimental. Confirm its current
status, license, release cadence, supported Ruby syntax, and public API.
Pin the version for the prototype and isolate it behind the semantic
adapter.

### Completeness of constant resolution

A resolved constant reference may not always identify one unique source
declaration. Dynamic definitions, conditional definitions, aliases, and
runtime modifications can make the result ambiguous. The engine must be
able to return multiple candidates or unresolved status.

### What does a require provide?

A required file may expose declarations from its own file and from files
it requires. It may also mutate existing objects. Unused-require
analysis must model the load closure while preserving uncertainty about
side effects.

### Standard library and default gems

Availability varies with Ruby version and packaging. Use
environment-aware metadata and configuration rather than a fixed list of
names.

### Optional dependencies

A conditional require may be the correct implementation of an optional
integration. Do not report it as unused simply because the optional
feature is not referenced in the current file's unconditional code.

### Native extensions

A `.so` or `.bundle` may not be parseable as Ruby source and may exist
specifically for side effects. Such requires should normally be
classified as uncertain unless explicit metadata describes their exports
and behavior.

### Aggregate entry points and public API conventions

Some gems intentionally require dependencies in a central entry point
and expect internal files to be loaded only through that entry point.
The project must choose and document whether its default policy is
strict per-file self-containment or aggregate-entry-point compatibility.
The two modes should not be conflated.

### Executing libraries to learn what they provide

The runtime snapshot loads each required library in a new Ruby process. This
is accurate, but it executes the code of that library. It is acceptable for
the libraries that the analyzed project already requires and runs, and it
must stay documented, visible in the report, and replaceable by static
metadata. It never runs the analyzed project itself.

### Performance and incremental analysis

Indexing all runtime dependencies may be expensive. Start with
correctness and measure before optimizing. Later improvements may
include caching by file content, dependency metadata caching, and
incremental re-analysis.

## Key design decisions

The following decisions are recommended for the prototype:

1.  **Build a standalone analyzer first**, not a RuboCop cop first.
2.  **Use Prism for syntax extraction**, subject to the supported Ruby
    version matrix.
3.  **Evaluate Rubydex as the semantic backend**, but verify its actual
    API and resolution behavior in Phase 0.
4.  **Hide the backend behind an adapter** to avoid architectural
    lock-in.
5.  **Analyze at file level**, with the target gem's `lib/` as the
    initial scope.
6.  **Model direct and transitive requires separately.**
7.  **Consider the full require closure** when deciding whether a
    require provides a referenced declaration.
8.  **Treat side-effect and dynamic loading as first-class
    uncertainty**, not as unused imports.
9.  **Do not auto-correct in the prototype.**
10. **Prioritize precision and explainability over aggressive
    detection.**
11. **Validate on real gems and fixture projects**, including
    deliberately injected defects.
12. **Keep runtime isolation tests complementary** to static analysis.

## Definition of done for the first useful prototype

The first useful prototype is complete when it can:

-   analyze a gem's `lib/` tree;
-   parse source files and collect static require directives;
-   resolve a meaningful subset of constant references to declarations;
-   identify likely missing direct requires;
-   identify likely unused requires without claiming that side-effect
    requires are safe to remove;
-   distinguish direct, transitive, unresolved, and dynamic loading;
-   provide source locations and evidence for each finding;
-   emit stable text and JSON output;
-   run against a real gem and a regression fixture suite;
-   document unsupported constructs and known limitations.

A prototype that only lists constants and require statements is a useful
feasibility experiment, but it is not yet a usable analyzer.

## References to verify before implementation

The initial discussion identified the following projects and community
evidence. Verify current URLs, releases, issues, and API documentation
before relying on them:

-   Shopify Rubydex --- semantic/static analysis toolkit for Ruby.
-   Prism --- Ruby parser and AST.
-   `rubocop-require_tools` --- existing RuboCop extension for
    require-related checks.
-   `degem` --- unused gem dependency analysis.
-   `lopper` --- multi-language unused-import analysis, including Ruby
    support.
-   `rigor` --- Ruby static analysis and type/reachability work.
-   `debride` and `leftovers` --- complementary dead-code analysis
    tools.
-   Ruby community discussion from 2005 concerning detection of extra
    `require` statements.
-   Reported `rubocop-require_tools` issues/PRs concerning
    included-module constants and `const_defined?`.
-   `degem` issue proposing AST-based analysis instead of regular
    expressions.

The project should maintain a small research log with exact URLs,
issue/PR identifiers, dates checked, and the conclusions each reference
supports. Do not repeat historical version or maintenance claims in
project documentation without rechecking them.

## Final positioning

The proposed project is not merely a tool that searches for unused
imports, nor just a modernization of an existing RuboCop cop.

It is a focused **Ruby loading-dependency analyzer**. Its distinctive
value is the combination of:

-   file-level dependency hygiene;
-   semantic constant attribution;
-   direct-versus-transitive require analysis;
-   conservative side-effect handling;
-   explainable diagnostics;
-   runtime isolation as a complementary check.

The first milestone is deliberately small: prove that a semantic index
can reliably connect constant references to declarations and source
files in a real gem. If that succeeds, the remaining work can be built
incrementally around a clear internal model. If it does not, the
feasibility spike should identify the missing capabilities before the
project commits to a backend.

The guiding principle is simple:

> Report what the analyzer can demonstrate, explain what it cannot
> determine, and never turn uncertainty into an unsafe recommendation.

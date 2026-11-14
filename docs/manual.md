# require_hygiene manual

<!-- gfm2pdf
common:
  metadata:
    subtitle: "User manual"
    author: "Laurent Martin"
-->

`require_hygiene` finds, in each Ruby file, the `require` and `require_relative` that are likely **missing** or likely
**unused**, and explains each finding. It is a Ruby gem with a command line tool and a library for other tools.

> [!NOTE]
> Version 0.1.0 (pre-release). The rules are described in
> [Baseline implementation](specification.md#baseline-implementation) in the specification. The confidence
> levels, the direct and transitive policies and the `uncertain` states of the specification are not implemented yet.

## Installation

Ruby 3.2 or later is required.

```shell
gem install require_hygiene
```

Or in the `Gemfile` of a project, to use the library or to pin a version in CI:

```ruby
group :development do
  gem 'require_hygiene', require: false
end
```

## Command line

```shell
require_hygiene analyze [PATH...] [options]
require_hygiene check-load [PATH...] [options]
require_hygiene version
```

### What is reported

| Rule | Meaning | Severity | Confidence |
| --- | --- | --- | --- |
| `missing_require` | A constant is used, but no `require` of the file provides it: the file works only because another file loaded it first. The message gives the `require` to add. | warning | `high` for a file of the project, `medium` for a library, `low` for a method added to a core class (`Hash#deep_merge`) |
| `unused_require` | Nothing that the required file or library provides is used. | info | `medium` |
| `duplicate_require` | The same `require` twice at the top of the file. | warning | `high` |

A `require` that provides nothing detectable (side effect, global variables) is never reported as unused, and neither
are the requires of a **facade**, a file that only requires other files.

> [!WARNING]
> To learn what a library provides, `analyze` loads each library that the analyzed files require, in a new Ruby
> process. This executes the code of that library, not the code of the analyzed project. Libraries that are not
> installed are ignored.

### Command `analyze`

`PATH` is a Ruby file or a folder (searched recursively for `*.rb`). Without a path, the `paths.include` patterns of
the [configuration](#configuration) are used: `lib/**/*.rb` by default. The folders of `paths.load_paths` (default:
`lib`) are where `require 'a/b'` means `a/b.rb`.

| Option | Values | Default | Description |
| --- | --- | --- | --- |
| `-c`, `--config` | file | `.require_hygiene.yml` if it exists | Configuration file. |
| `-f`, `--format` | `text`, `json` | `text` | Output format. |
| `--min-confidence` | `low`, `medium`, `high` | `low` | Hide findings below this confidence. |
| `--fail-on` | `never`, `missing`, `unused`, `duplicate`, `warning`, `any` | `never` | Exit with status 1 if there is a new finding of this kind, or of severity `warning`. |
| `--baseline` | file | `baseline.file`, or `.require_hygiene_todo.yml` with `--write-baseline` | Known findings, not reported. |
| `--write-baseline` | | off | Record the current findings in the baseline file, then exit. |
| `-V`, `--verbose` | | off | In text format, also list the files and the `require` directives found. |

Example:

```shell
$ require_hygiene analyze lib/defects/c.rb
lib/defects/c.rb:2:1: duplicate_require (high) require 'defects/a' is already there
lib/defects/c.rb:3:1: unused_require (medium) require 'defects/b': nothing provided by this file is used
lib/defects/c.rb:9:15: missing_require (high) Defects::D is used, but not provided by a require of this file: add require 'defects/d'
3 finding(s) in 1 file(s)
```

### Baseline: fix progressively

A code base with many findings cannot be fixed at once. As with `.rubocop_todo.yml`:

```shell
require_hygiene analyze --write-baseline          # record the current findings
require_hygiene analyze --fail-on any             # CI: only new findings fail
```

An entry of the baseline file has no line number, so it still matches when the code moves. When a finding is fixed,
`analyze` lists its entry as fixed: remove it.

### Command `check-load`

Loads each file alone in a new Ruby process, with the `paths.load_paths` folders in the load path. A file that fails
depends on the load order, or on something else that its own requires do not load. A failure caused by a library that
is not installed is shown as optional and does not fail the command.

```shell
$ require_hygiene check-load
lib/defects.rb: cannot be loaded alone: .../lib/defects/c.rb:9:in '<class:C>': uninitialized constant Defects::C::D (NameError)
lib/defects/c.rb: cannot be loaded alone: .../lib/defects/c.rb:9:in '<class:C>': uninitialized constant Defects::C::D (NameError)
3 file(s) loaded alone, 0 skipped (optional library), 2 error(s)
```

This complements `analyze`: it cannot say which `require` is missing, but it proves that the file really fails.

### Exit status

| Status | Meaning |
| --- | --- |
| `0` | Success: no new finding at or above the `--fail-on` threshold. |
| `1` | At least one new finding at or above the `--fail-on` threshold, or (`check-load`) a file that cannot be loaded alone. |
| `2` | Error: a path does not exist, a file has a syntax error, the configuration is invalid, or the command line is wrong. |

### Directives that are recognized

| Source | Recognized as |
| --- | --- |
| `require 'json'`, `require_relative 'client'` | A static directive, with its line and column. |
| `require name`, `require "a/#{name}"` | A dynamic directive: no target is ever guessed. |
| `send(:require, name)` | A dynamic directive. |
| `obj.require 'x'` | Not a directive: only calls without receiver are `Kernel#require`. |
| A require inside `if`, `unless`, a modifier, or `begin ... rescue` | Marked as **conditional**, as it can express an optional feature. |

## Output

### Text

One line per finding, `file:line:column: rule (confidence) message`, then a summary.

### JSON

`--format json` writes one document, with a version so that CI tools can depend on it:

```json
{
  "schema_version": 1,
  "rules": ["missing_require", "unused_require", "duplicate_require"],
  "files": ["lib/defects/c.rb"],
  "requires": [
    {"file": "lib/defects/c.rb", "kind": "require", "path": "defects/a", "line": 1, "column": 1, "static": true, "conditional": false, "lazy": false}
  ],
  "diagnostics": [
    {
      "schema_version": 1,
      "rule": "missing_require",
      "file": "lib/defects/c.rb",
      "location": {"start_line": 9, "start_column": 15},
      "confidence": "high",
      "severity": "warning",
      "subject": {"constant": "Defects::D"},
      "evidence": {"candidates": ["defects/d"], "direct_requires": ["defects/a", "defects/b"]},
      "message": "Defects::D is used, but not provided by a require of this file: add require 'defects/d'"
    }
  ]
}
```

Each entry of `diagnostics` follows the diagnostic schema of the [Specification](specification.md): `rule`, `file`,
`location`, `confidence` (`low`, `medium`, `high`), `severity` (`info`, `warning`, `error`), `subject`, `evidence` and
`message`. Lines and columns start at 1.

## Configuration

The file `.require_hygiene.yml` in the current folder, or the file given with `--config`. All settings are optional,
the options of the command line win.

```yaml
paths:
  include:
    - lib/**/*.rb
  exclude:
    - lib/**/version.rb
  load_paths:
    - lib
allow:
  # Constants that a require provides, in addition to what it defines or loads
  extra_provides:
    my_gem/colors: [Colors]
  # Source pattern that shows the use of a library that provides no constant
  usage_patterns:
    pp: '\bpp[ (]'
baseline:
  file: .require_hygiene_todo.yml
output:
  format: text
  minimum_confidence: low
```

| Setting | Default | Description |
| --- | --- | --- |
| `paths.include` | `lib/**/*.rb` | Files analyzed when the command has no path. |
| `paths.exclude` | none | Files not checked (they can still provide constants). |
| `paths.load_paths` | `lib` | Folders where `require 'a/b'` means `a/b.rb`. A folder that does not exist is ignored. |
| `allow.extra_provides` | none | `require name` => list of constants it provides, in addition to what it defines or loads. |
| `allow.usage_patterns` | see below | `library name` => regular expression of the source that shows its use, for a library without constants. |
| `baseline.file` | none | Known findings, not reported. |
| `output.format` | `text` | `text` or `json`. |
| `output.minimum_confidence` | `low` | Findings below this confidence are not reported. |
| `policy.missing_requires` | `self_contained` | Reserved: only the self-contained policy exists. |

Usage patterns are built in for `English`, `pp`, `time`, `yaml`, `json`, `tmpdir` and `io/console`, and the ones of the
configuration are added to them.

## Use as a library

```ruby
require 'require_hygiene'

config = RequireHygiene::Configuration.load('.require_hygiene.yml')
report = RequireHygiene::Analyzer.new(config).analyze(['lib'])

report.diagnostics.each { |d| puts "#{d.file}:#{d.line}: #{d.rule}: #{d.message}" }
puts JSON.pretty_generate(report.to_h)
```

| Object | Description |
| --- | --- |
| `RequireHygiene::Configuration.load(file = nil, overrides = {})` | Settings from the defaults, a file, and overrides. |
| `RequireHygiene::Analyzer#analyze(paths = [])` | Returns a `Report`. |
| `RequireHygiene::Report` | `files`, `directives`, `diagnostics`, `rules`, and `to_h` for the JSON form. |
| `RequireHygiene::Diagnostic` | A finding. `to_h` follows the JSON schema. |
| `RequireHygiene::Checker` | The rules, without configuration: `new(load_paths:, files:).check` returns the findings. |
| `RequireHygiene::SourceScanner.scan(file)` | What one file requires, defines and references. |
| `RequireHygiene::IsolationCheck.run(files:, load_paths:)` | Files that cannot be loaded alone. |
| `RequireHygiene::Baseline` | Known findings: `.write(file, diagnostics)`, `#partition(diagnostics)`. |
| `RequireHygiene::Error` | Base class of all errors. `ConfigurationError` is a subclass. |

The library never prints, never calls `exit`, and does not load the command line: `require 'require_hygiene'` does not
load Thor. The JSON form (`to_h`) is the stable contract, the Ruby classes can still change before version 1.0.

## Complementary tools

`require_hygiene` does not replace RuboCop, and RuboCop does not replace it. Checked on RuboCop 1.92.2, Ruby 4.0.9
(see the [Research log](research_log.md)):

| Tool | What it checks | What it does not check |
| --- | --- | --- |
| `Lint/DuplicateRequire` (RuboCop, enabled by default) | The same `require` twice at the top level of a file. | A `require` in a method that repeats one at the top: `duplicate_require` of this tool reports it, RuboCop does not. |
| `Style/RequireOrder` (RuboCop, disabled by default) | Alphabetical order of consecutive `require` lines. | Whether a `require` is missing or unused. |
| `Style/RedundantFileExtensionInRequire` (RuboCop, enabled by default) | A useless `.rb` in `require 'a.rb'`. | Same. |
| `require_hygiene analyze` | Missing, unused and duplicate `require`, from the constants that the code uses. | Order, file extension, style. |
| `require_hygiene check-load` | Proves that a file fails when loaded alone. | Which `require` is missing, see [Command `check-load`](#command-check-load). |
| `ruby -w` | A warning `circular require considered harmful` when a file is loaded while it is already loading. | It only appears when the cycle is actually executed, and the code of the project runs. |

RuboCop did not report a constant used without its `require` in the test made (`SecureRandom` in a class), and
`analyze` did.

`require_hygiene` does not enforce a specific style for internal file loading: the tool works with both `require`
resolved against load paths and `require_relative`.

## Best practices

While `require_hygiene` supports various loading styles, the following rules represent standard modern Ruby best practices:

- **Prefer `require_relative` for internal files**: Always use `require_relative` when loading files inside your own project or gem. It resolves paths directly relative to the current file's directory (`__dir__`) without scanning `$LOAD_PATH`, making loading faster, deterministic, and immune to naming collisions across gems.
- **Reserve `require` for external gems and standard libraries**: Only use standard `require` for third-party gems (managed via Bundler) or Ruby's built-in standard library (such as `json`, `csv`, or `net/http`). Installed gems register their `lib/` directory in `$LOAD_PATH`, which is what `require` is designed to look up.
- **Never modify `$LOAD_PATH` (`$:`) inside application code**: Avoid modifying `$LOAD_PATH` dynamically (such as `$LOAD_PATH.unshift('lib')`). Rely on `require_relative`, Bundler, or a proper autoloader instead. Modifying `$LOAD_PATH` in application code introduces global state side-effects that can break dependencies.
- **Autoloaders (Zeitwerk)**: In projects using an autoloader (like Zeitwerk in Rails applications or modern gems), explicit `require` and `require_relative` calls for internal constants should generally be omitted, as constants are loaded on demand.
- **Put the `require` lines at the top of the file, and sort them**: A reader audits the dependencies of a file in one place, and a sorted list makes a duplicate or a missing line easy to see. RuboCop has a cop for the sorting, `Style/RequireOrder`, which is disabled by default (see [Organizing `require` statements](#organizing-require-statements)).
- **Group the `require` lines by origin (a team convention, not a community rule)**: Standard library first, then third-party gems, then internal files (`require_relative`), one blank line between groups, each group sorted. The Ruby style guide and RuboCop do not define this grouping, see below.

### Organizing `require` statements

```ruby
# frozen_string_literal: true

require 'json'
require 'uri'

require 'faraday'
require 'nokogiri'

require_relative 'models/user'
```

What the community and the tools say, checked on RuboCop 1.92.2 (see the [Research log](research_log.md)):

| Practice | Status | Detected by RuboCop | Corrected by RuboCop |
| --- | --- | --- | --- |
| Alphabetical order of `require` lines | Supported: `Style/RequireOrder` exists, but is disabled by default. | Yes, within a block of lines with no blank line between them, for `require` and `require_relative` separately. | Yes, with `-A` only: the correction is unsafe, because it changes the load order. |
| `require` lines at the top of the file | Common practice. No cop checks it. | No. | No. |
| Group by standard library, gems, internal files | Convention of other languages (for example the import order of PEP 8 in Python). Not in the Ruby style guide, and no cop in RuboCop itself. | No, with RuboCop alone: a blank line only starts a new section for the sorting, it does not say what the group contains. Yes, with the example cop of this project, see below. | Same: only with the example cop (unsafe). |

To enable the sorting, in `.rubocop.yml`:

```yaml
Style/RequireOrder:
  Enabled: true
```

With the blank lines between groups, `Style/RequireOrder` sorts each group separately, so it accepts the layout above and
reports a line out of order inside a group. It does not move a line from one group to another.

Sorting can change behavior when a file relies on the load order, for example a `require` that must run before a file
that patches it. Review the result of `rubocop -A --only Style/RequireOrder` before committing it.

#### Example cop: `Style/RequireGrouping`

[`examples/require_grouping_cop.rb`](../examples/require_grouping_cop.rb) is an example RuboCop cop, not part of the gem
(like [`examples/prefer_require_relative_cop.rb`](../examples/prefer_require_relative_cop.rb)). It detects and corrects the
grouping and the sorting together: standard library, gems, internal files, one blank line between groups, each group
sorted.

```yaml
require:
  - ./examples/require_grouping_cop.rb
Style/RequireGrouping:
  Enabled: true
  LoadPaths:
    - lib
  ExtraStandardLibrary:
    - set
  Sort: true
```

| Setting | Meaning |
| --- | --- |
| `LoadPaths` | Directories where a `require 'x'` is an internal file (default `lib`). Relative to the directory where RuboCop runs. |
| `ExtraStandardLibrary` | Names that are standard library for you but are not found in the library directories of the running Ruby (default `set`). |
| `Sort` | `false` to only group, without sorting inside a group (default `true`). |

How a `require` is classified:

- `require_relative`, or `require` of a file found in `LoadPaths`: internal.
- `require` of a file found in the library directories of the running Ruby (`RbConfig::CONFIG['rubylibdir']` and
  `['rubyarchdir']`): standard library.
- Any other `require`: gem. This includes the bundled gems that are no longer in these directories, such as `csv` or
  `bigdecimal` with Ruby 4.0. The classification depends on the Ruby that runs RuboCop.

What it never moves, to avoid changing the behavior or losing a comment:

- A `require` that is conditional (`require 'a' if b`), dynamic (`require name`), written with a receiver, on several
  lines, or followed by code on the same line.
- A `require` with a comment on the line above. It ends the block of lines being sorted.
- Anything that is not a block of at least two consecutive `require` lines at the top level of the file. A `require`
  inside a `module`, a method or an `if` is not checked.

Like `Style/RequireOrder`, the correction is unsafe because it changes the load order. A second run of the correction
changes nothing. The cop is not covered by an automated test: see the [Research log](research_log.md) for what was run.

#### Example cop: `Style/RequireRelativeFirst`

[`examples/require_relative_first_cop.rb`](../examples/require_relative_first_cop.rb) is an example RuboCop cop, not part
of the gem. It puts `require_relative` before `require` in each block of consecutive top-level `require` lines, the
reverse of the order of `Style/RequireGrouping`: do not enable both.

Why: `require` is global to the process. A gem or a standard library loaded by an earlier line can hide that a local
file does not require what it uses. When the local files are loaded first, such a missing dependency fails at load time.
This is only a help, limited to what is used while the file is loaded. The reliable check is `check-load`, which loads
each file alone.

```yaml
require:
  - ./examples/require_relative_first_cop.rb
Style/RequireRelativeFirst:
  Enabled: true
  Pinned:
    - aspera/coverage
```

| Setting | Meaning |
| --- | --- |
| `Pinned` | Files that must stay first, whatever the kind of `require` (for example the code coverage). An entry matches the whole argument or its last path segments. |

A block is a series of `require` or `require_relative` lines with a string argument, each alone on its line (a comment
at the end of the line is kept), with no blank line, comment or other code between them. The order inside each kind is
kept. A `require` in a method, a condition or a `begin/rescue` is not touched. The correction is unsafe (`-A` only),
because it changes the load order. The cop is covered by `test/require_relative_first_cop_test.rb`.

## Limitations

- Constants are resolved by name and lexical nesting, not through inheritance or included modules. A constant that
  cannot be resolved is ignored, never reported.
- `missing_require` applies the self-contained policy: a file must require what it uses itself, even if another
  file would load it. On a code base that relies on an aggregate entry point, most findings are of this kind: use the
  baseline.
- The constants of a library are learned only from the `require` found in the analyzed files. If no analyzed file
  requires `securerandom`, a use of `SecureRandom` is not reported as missing; if one file requires it, the other
  files that use it without their own `require` are reported.
- Dynamic loading (`require name`, `autoload`, `eval`) is recorded as dynamic, never resolved.
- The analysis loads libraries, see the warning in [What is reported](#what-is-reported).
- The tool never changes a file: inserting or removing a `require` can change the load order or remove a required side
  effect.

See the [Specification](specification.md) for what is planned and why the tool is conservative.

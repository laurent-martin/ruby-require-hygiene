# Research log

<!-- gfm2pdf
common:
  metadata:
    subtitle: "Research log"
    author: "Laurent Martin"
-->

This log records what was **checked**, when, and what it supports, as required by the
[Specification](specification.md). A claim that is not in this log must not be repeated in the documentation of the
gem without being checked again.

## Registry facts (14 November 2026)

Source: `https://rubygems.org/api/v1/gems/<name>.json`.

| Gem | Latest version | License | Released | Note |
| --- | --- | --- | --- | --- |
| `require_hygiene` | none | | | Name is free: the API answers 404. |
| `rubydex` | 0.4.4 | MIT | 2026-10-28 | Required Ruby `>= 3.2, < 4.1.dev`. Precompiled for arm64-darwin, x86_64-darwin, aarch64-linux, x86_64-linux, x64-mingw-ucrt. |
| `prism` | 2.1.0 | MIT | 2026-10-28 | Installed on the development machine: 1.9.0. |
| `thor` | 1.5.0 | MIT | 2026-01-06 | |
| `rubocop-require_tools` | 0.3.0 | MIT | 2026-09-30 | Maintained again in 2026 (see the section below). About 1.35 million downloads. Only one cop: `MissingRequireStatement`. |
| `degem` | 0.3.0 | MIT | 2024-12-20 | Bundle-level analysis. |
| `debride` | 1.15.2 | MIT | 2026-04-20 | Dead code. |
| `leftovers` | 0.12.2 | MIT | 2023-03-24 | Dead code. |
| `rigor` | 0.0.2 | none | 2012-02-12 | **Not the project meant by the specification**: this is an unrelated 2012 gem. The Ruby static analysis project called `rigor` must be located again before it is cited. |
| `lopper` | not on RubyGems | | | Multi-language tool: it is not a gem, its source repository must be located. |

## Spike 1: Rubydex 0.4.4 on a fixture gem (14 November 2026)

Environment: Ruby 4.0.9 on arm64-darwin, Rubydex 0.4.4, `rbs` 4.2.0.

Fixture, three files:

```ruby
# lib/ex.rb
require 'json'
require_relative 'ex/a'
require_relative 'ex/b'

# lib/ex/a.rb
module Ex
  class A; end
end

# lib/ex/b.rb
module Ex
  class B
    def x = [A.new, Faraday, JSON, String]
  end
end
```

Calls: `Graph#index_all(files)`, `Graph#resolve`, then `Graph#constant_references`.

| Reference in `b.rb` | Result | Meaning for the analyzer |
| --- | --- | --- |
| `A` | resolved to `Ex::A`, declared in `lib/ex/a.rb` | Lexical lookup works: this is the base case of a missing-require check. |
| `A` (second record, same position) | resolved to `Ex::A::<A>` | Internal record for the singleton class: to be normalized away. |
| `Faraday`, `JSON` | unresolved | Not indexed. The analyzer must treat "outside the indexed scope" as a distinct state. |
| `String` | unresolved | Resolved when the RBS core definitions (`rbs` gem, `core/`) are indexed: the declaration is then in `string.rbs`. |

Other results:

- Positions (`start_line`, `start_column`, `end_line`, `end_column`) are **zero-based**: `Faraday` on the third line
  is reported at line 2, columns 20 to 27.
- `Graph#resolve_require_path('ex/a', [lib])` returns the document `file:///.../lib/ex/a.rb`.
  `resolve_require_path('json', [lib])` returns `nil`: the standard library is not on the given load paths.
- `Graph#diagnostics` was empty for valid code. The gem has rules `dynamic_constant_reference`, `dynamic_ancestor`,
  `parse_error` and `parse_warning` that can serve as uncertainty evidence.
- `Rubydex::Graph.configure_for_workspace` and `#index_workspace` read the Bundler lockfile to index
  dependencies. The analyzer should instead pass an explicit list of files and load paths, to be reproducible.

Conclusion: the facts needed for **missing-require** analysis on project files are available. Not yet verified:
declaration lists per file for **unused-require** analysis, behavior with `include` and `prepend`, `autoload`,
conditional definitions, and a real gem. See Phase 0 in the [Specification](specification.md).

## RuboCop and Ruby checks on `require` (14 November 2026)

Environment: RuboCop 1.92.2, Ruby 4.0.9 on arm64-darwin. Each line was run on a small file, with a `.rubocop.yml` that
only sets `NewCops: disable`, then compared with `require_hygiene analyze`.

| Claim | Result |
| --- | --- |
| `Lint/DuplicateRequire` exists and is enabled by default | Yes (`rubocop --show-cops`: `Enabled: true`, added in 0.90). It reported the second `require 'json'` at the top of a file. |
| `Lint/DuplicateRequire` reports a `require` in a method that repeats one at the top | **No**: no offense. `require_hygiene` reports it as `duplicate_require`. |
| `Style/RequireOrder` exists, default state | Exists (added in 1.40), `Enabled: false` by default. Enabled, it reported `require 'foo.rb'` placed after `require 'set'`. It checks order only. |
| `Style/RedundantFileExtensionInRequire` | Exists and is enabled by default: it reported `require 'foo.rb'` with no setting for it. The configuration of this project (`rubocop-shopify`) disables it. |
| RuboCop reports a constant used without its `require` | **No** for `SecureRandom` in a method (only `Style/Documentation`). `require_hygiene` reports `missing_require`, but only when another analyzed file requires `securerandom`: with a single file that does not require it, it reports nothing. |
| `load` runs the file again, `require` does not | Yes: with `ruby -w`, a second `load` of a file that defines a method gives "previous definition of f was here". |
| Circular `require` gives a warning | Yes: `ruby -w` prints "loading in progress, circular require considered harmful". Not checked without `-w`. |
| The Ruby style guide has a rule on `require` | **No**: `README.adoc` of `rubocop/ruby-style-guide` (master, 14 November 2026) has no rule on `require`, order or grouping. |
| RuboCop has a cop that groups `require` by origin | **No**: `rubocop --show-cops` lists, for `require`, only `Lint/DuplicateRequire`, `Lint/NonDeterministicRequireOrder`, `Lint/RedundantRequireStatement`, `Lint/RequireParentheses`, `Lint/RequireRangeParentheses`, `Lint/RequireRelativeSelfPath`, `Style/RedundantFileExtensionInRequire` and `Style/RequireOrder`. |
| `Style/RequireOrder` accepts the layout standard library, gems, `require_relative`, with one blank line between sorted groups | Yes: no offense on such a file. |
| `Style/RequireOrder` checks the group of a `require` | **No**: on `require_relative 'my_gem/models'`, `require 'nokogiri'`, `require 'uri'`, `require 'json'`, `require 'faraday'` it reported only `json` and `faraday` as out of order. A `require_relative` placed before the `require` lines was not reported. |
| `Style/RequireOrder` autocorrects | Yes with `rubocop -A`: `SafeAutoCorrect: false`, and the source says the correction changes the execution order. It sorted the four `require` lines of the file above and left `require_relative` first. |
| Example cop `examples/require_grouping_cop.rb` (`Style/RequireGrouping`) | Run by hand on small files (RuboCop 1.92.2, Ruby 4.0.9): it reported a `require_relative` before a `require`, a gem before the standard library, and an unsorted block. With `-A` it produced three groups separated by one blank line, and kept a trailing comment on its line. A second run reported nothing. No error on an empty file, a one-line file, a file without `require`, or a `require` inside a `module`. It left alone `require 'b' if ENV['X']`, `require name` and a `require` with a comment on the line above. Not covered by an automated test. |
| Classification used by the example cop | `set` is loaded by Ruby 4.0 without a `set.rb` in `rubylibdir`, so it is listed in `ExtraStandardLibrary`. `csv` and `bigdecimal` have no file in `rubylibdir` (they are bundled gems) and are classified as gems. |
| Use together with `Style/RequireOrder` | Not verified. The two were run together only on a file that the example cop had already corrected: `Style/RequireOrder` still reported a conditional `require` and a `require` placed after it, which the example cop leaves alone on purpose. |

Not checked, so not stated in the documentation as verified: that `require 'rubygems'` is redundant, the cost of
`Bundler.require`, the effect of `$LOAD_PATH` changes, and the risk of a `require` with a user-supplied string. The
[Manual](manual.md) chapter "Best practices" lists `require_relative` for internal files, Zeitwerk and `$LOAD_PATH` as
general advice, not as results of this log. The [Specification](specification.md) does not impose a loading style.

## `rubocop-require_tools` history (14 November 2026)

Source: `https://github.com/milch/rubocop-require_tools` and `https://api.github.com/repos/milch/rubocop-require_tools/issues`.
Only the repository page, the issue and pull request descriptions, and the RubyGems API were read, not the code.

| Claim | Result |
| --- | --- |
| The README lists more than one cop | **No**: "Currently it will only check whether there are possibly any missing requires". The gem has no unused-require check. |
| Constants of included modules are resolved | **Yes**, since [PR 7](https://github.com/milch/rubocop-require_tools/pull/7), merged 2026-09-30. The description reports 70 offenses falling to none on fastlane `produce/lib/produce/service.rb`. |
| Constants guarded by `defined?` or `const_defined?` are skipped | **Yes**, since [PR 8](https://github.com/milch/rubocop-require_tools/pull/8), merged 2026-09-30. A check on `Foo` does not cover `Foo::Bar`. |
| Aliased constants (`Foo = Bar::Baz`) are resolved | **Yes**, since [PR 4](https://github.com/milch/rubocop-require_tools/pull/4) (issue 3), merged 2026-05-27. |
| The cop uses the current RuboCop base class | **Yes**, since [PR 6](https://github.com/milch/rubocop-require_tools/pull/6), merged 2026-09-30. RuboCop 1.0 is the minimum. |
| The project is maintained | Yes, in 2026: pull requests 4, 5, 6, 7 and 8 were merged between May and September 2026, most of them the day they were opened. Issue 3 (November 2025) describes the gem as having had about seven years with no work. This was not checked in the commit history. |

Consequence: the limitations on included modules and `const_defined?`, which the Specification listed as leads, are
fixed upstream. They no longer support the positioning of this project. What remains different is the unused-require
rule, the explained JSON output, the isolation check and the baseline.

## Open research items

| Item | Needed for |
| --- | --- |
| Behavior of `rubocop-require_tools` 0.3.0 and `require_hygiene` on the same files (fastlane, fixtures): false positives and false negatives of each. | Positioning, Specification chapter "User need and existing ecosystem evidence". |
| URL of the 2005 Ruby community discussion. | Same. |
| `degem` issue about AST-based analysis. | Same. |
| Source of `lopper` and of the Ruby static analysis project named `rigor`. | Same. |
| Behavior of Rubydex on a real gem, with and without RBS core definitions. | Phase 0 exit criteria. |
| Standard library and default gem metadata by Ruby version (`Gem::Specification.default_stubs`, `RbConfig`). | Missing-require exclusions. |

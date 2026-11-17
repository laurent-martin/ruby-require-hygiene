# Changelog

## 0.1.0.pre

Released: [Place date of release here]

### New

- Gem `require_hygiene`: library (`Analyzer`, `Checker`, `Configuration`, `Report`, `Diagnostic`, `SourceScanner`,
  `RuntimeSnapshot`, `IsolationCheck`, `Baseline`) and command line (`analyze`, `check-load`, `version`) built with Thor.
- Rules `missing_require`, `unused_require` and `duplicate_require`.
- Confidence levels, text and JSON output (`schema_version` 1), configuration file `.require_hygiene.yml`, exit status
  for CI (`--fail-on`).
- Baseline file of known findings (`--write-baseline`, `--baseline`), to fix progressively.
- `check-load`: each file loaded alone in a new process.
- Documentation: manual, specification, research log, development guide, PDF generation with `rake doc:pdf`.
- Manual: best practices on the order and the grouping of `require` lines, with what RuboCop detects and corrects.
- Example RuboCop cop `Style/RequireGrouping` (`examples/require_grouping_cop.rb`): detects and corrects the grouping
  (standard library, gems, internal files) and the sorting of `require` lines. Not part of the gem.
- Example RuboCop cop `Style/RequireRelativeFirst` (`examples/require_relative_first_cop.rb`): puts `require_relative` before
  `require`, with a `Pinned` list of files that stay first. Not part of the gem.
- Community files: `CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`, `SECURITY.md`, issue and pull request templates.
- CI: least-privilege permissions, actions pinned by commit SHA, Dependabot, `bundler-audit`, macOS job, gem build and
  install check, SimpleCov coverage report, API documentation check.
- Test coverage with SimpleCov (`coverage/`, minimum 80% of lines) and API documentation with YARD (`rake yard`, `rake yard:check`).
- Standard libraries (default and bundled gems) always loaded: a constant such as `Date` is reported as missing even when
  no checked file requires its library, whatever the libraries that happen to load it with this Ruby.
- Ownership of the constants of a library from a trace of `require`: a constant that appeared while another known library
  was being required is not owned (`Date` is not provided by `psych`, `Digest::SHA256` not by `pstore`); facades provide
  the library they are the entry point of (`yaml` provides `Psych`, `net/https` provides `Net::HTTP`).
- Gem metadata `source_code_uri` and `bug_tracker_uri`, upper bound `< 2` on `prism`. `bin/setup` and `bin/console`.

# require_hygiene

[![Gem Version](https://badge.fury.io/rb/require_hygiene.svg)](https://rubygems.org/gems/require_hygiene)
[![Test](https://github.com/laurent-martin/ruby-require-hygiene/actions/workflows/test.yml/badge.svg)](https://github.com/laurent-martin/ruby-require-hygiene/actions/workflows/test.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Ruby](https://img.shields.io/badge/ruby-%E2%89%A5%203.2-red.svg)](https://www.ruby-lang.org)

Static analysis of the `require` hygiene of Ruby files: finds, in each file, the `require` and `require_relative` that
are likely missing or likely unused, with explained findings and a confidence level. Conservative by design: it
reports what it can demonstrate and says what it cannot determine.

It is a Ruby gem with a command line tool (`require_hygiene`, built with Thor) and a library that other tools can use.

> [!NOTE]
> Pre-release (0.1.0). The more advanced analysis planned in the specification
> (direct and transitive policies, uncertainty states, semantic backend) is not implemented yet.

## Installation

Ruby 3.2 or later is required.

```shell
gem install require_hygiene
```

Or in the `Gemfile` of a project:

```ruby
group :development do
  gem 'require_hygiene', require: false
end
```

## Usage

```shell
require_hygiene analyze lib            # likely missing and likely unused require, with explanations
require_hygiene analyze lib --format json --fail-on high
require_hygiene check-load lib         # each file loaded alone in a new process
require_hygiene version
```

As a library:

```ruby
require 'require_hygiene'
```

Options, configuration file, JSON output and library API: see the [Manual](docs/manual.md). The API documentation is
generated with `rake yard`.

## Documentation

| Document | Content |
| --- | --- |
| [Manual](docs/manual.md) | Installation, command line, configuration, JSON output, use as a library, best practices. |
| [Specification](docs/specification.md) | Problem, design, algorithms, confidence model, test strategy, plan. |
| [Research log](docs/research_log.md) | What was verified, when, and what it supports. |
| [Development guide](docs/development.md) | Build, test, generate the PDF documentation, release. |
| [Changelog](CHANGELOG.md) | Changes by version. |

PDF versions of the documents are generated with `rake doc:pdf`, see the [Development guide](docs/development.md).

## Contributing

Bug reports and pull requests are welcome, see [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md). To report a vulnerability, see [SECURITY.md](SECURITY.md).

## License

Apache License 2.0, see [LICENSE](LICENSE).

# Contributing

Thank you for your interest in `require_hygiene`. By participating, you agree to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Reporting a problem

- Bug or false positive/negative: open an [issue](https://github.com/laurent-martin/ruby-require-hygiene/issues/new/choose)
  with the Ruby version, the version of the gem, the command, and a minimal Ruby file that reproduces it.
- Security vulnerability: do not open a public issue, see [SECURITY.md](SECURITY.md).

## Proposing a change

1. Fork the repository and create a branch from `main`.
1. Set up the environment and run the checks, see the [Development guide](docs/development.md):

    ```shell
    bundle install
    bundle exec rake
    bundle exec bin/require_hygiene analyze lib
    ```

1. Add a test. A defect found on a real gem becomes a small fixture in `test/fixtures/`, with the expected result.
1. Describe the change in `CHANGELOG.md`, in the first section, under `### New` or `### Fixed`.
1. Open a pull request. The CI runs the tests and RuboCop on Ruby 3.2 to 4.0.

`bundle exec rake` runs the tests and RuboCop, and must pass without offense. Test coverage is reported by SimpleCov in
`coverage/`. The API documentation is generated with `bundle exec rake yard`.

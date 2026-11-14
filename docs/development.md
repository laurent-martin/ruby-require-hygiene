# Development guide

<!-- gfm2pdf
common:
  metadata:
    subtitle: "Development guide"
    author: "Laurent Martin"
-->

How to build, test, document and release `require_hygiene`.

## Setup

```shell
git clone https://github.com/laurent-martin/ruby-require-hygiene.git
cd ruby-require-hygiene
bundle install
```

Ruby 3.2 or later. On Ruby 3.2 only the tests run: RuboCop (`rubocop-shopify`) requires Ruby 3.3 and is not installed. The command line from the sources: `bundle exec bin/require_hygiene analyze lib`.

## Layout

| Path | Content |
| --- | --- |
| `bin/require_hygiene` | Executable: only calls `RequireHygiene::CLI`. |
| `lib/require_hygiene.rb` | Library entry point, does not load Thor. |
| `lib/require_hygiene/` | Library: `source_scanner`, `checker`, `runtime_snapshot`, `isolation_check`, `baseline`, `analyzer`, configuration, report. |
| `lib/require_hygiene/cli.rb` | Thor command line, loaded by `bin/` only. |
| `test/` | Minitest tests, `test/fixtures/` contains small projects, with deliberate defects, that are analyzed. |
| `docs/` | Markdown documents: this guide, the [Manual](manual.md), the [Specification](specification.md) and the [Research log](research_log.md). |
| `rakelib/doc.rake` | Documentation tasks. |

Rules of the design (thin CLI, library without side effects, errors as exceptions, stable JSON, replaceable backends)
are in the chapter "Packaging, library API and CLI" of the [Specification](specification.md).

## Tasks

`bundle exec rake -T` lists them.

| Task | Description |
| --- | --- |
| `rake` | `test` and `rubocop`. |
| `rake test` | Run the Minitest suite. |
| `bundle exec bin/require_hygiene analyze lib` | The gem checks itself: it must report nothing. |
| `rake rubocop` | Lint. |
| `rake yard` | Generate the API documentation in `doc/` (configuration in `.yardopts`). |
| `rake yard:check` | Generate the API documentation and fail on any YARD warning, as CI does. |
| `bundle exec bundler-audit check --update` | Check the dependencies for known vulnerabilities, as CI does. |
| `rake build` | Build `pkg/require_hygiene-<version>.gem`. |
| `rake release:run[version,next_version]` | Create a release: version, changelog, tag, GitHub release, next development cycle. |
| `rake release:yank[version]` | Yank a version from rubygems.org. |
| `rake release` | Bundler: tag, build and push the gem to rubygems.org. Done by the CI, see [Release](#release). |
| `rake doc:pdf` | Generate `docs/*.pdf`. |
| `rake doc:check` | Check the documents as CI does. |
| `rake doc:renumber` | Renumber the figures of `docs/*.md`. |
| `rake clean` | Remove the generated PDF files. |

## Documentation

The documents are GitHub-flavored Markdown, written to read well on GitHub, and converted to PDF with
[gfm2pdf-toolchain](https://github.com/laurent-martin/gfm2pdf-toolchain), which uses `pandoc`.

1. Install the tools: `pandoc`, and a PDF engine, LuaLaTeX (default) or Typst. See the requirements of the toolchain.
1. Clone the toolchain and set the environment variable, e.g. in the shell profile:

    ```shell
    export GFM2PDF_HOME=$HOME/workspace/gfm2pdf-toolchain
    ```

1. Generate the PDF files:

    ```shell
    bundle exec rake doc:pdf
    GFM2PDF_ENGINE=typst bundle exec rake doc:pdf
    ```

Each `docs/<name>.md` gives `docs/<name>.pdf`, ignored by git. The title of the cover is the first level 1 heading,
and the subtitle and author are in the `<!-- gfm2pdf ... -->` comment at the top of the file. Chapters are numbered by
the toolchain: do not number headings by hand.

`rake doc:check` runs the toolchain in mode `check`: a warning of `pandoc`, of a filter or of the PDF engine is an
error, and internal links (`[text](#anchor)`) must match a heading both on GitHub and in the PDF. Use it in CI.

`README.md` is not converted: it only describes the project and links to the documents.

> [!NOTE]
> Links to another document, e.g. `[Manual](manual.md)`, work on GitHub. In a PDF they stay links to the file: the
> documents are independent PDF files.

## Tests

`rake test` writes the coverage report of SimpleCov in `coverage/index.html` (lines and branches) and fails under 80% of
lines. The tests of the command line run it in a new process: these runs are not counted.

Tests are in `test/*_test.rb`. A defect found on a real gem becomes a small fixture in `test/fixtures/`, with the
expected result, as required by the regression policy of the [Specification](specification.md). Fixtures are analyzed,
never executed, and are excluded from RuboCop.

## Release

### Versioning

[Semantic versioning](https://semver.org/). Between releases, the version in `lib/require_hygiene/version.rb` is the
next version with the suffix `.pre` (e.g. `0.2.0.pre`), and the first section of `CHANGELOG.md` has the same title and
the line `Released: [Place date of release here]`. Describe each change in this section, under `### New` or `### Fixed`.

### Create a release

On GitHub: Actions, "New Release on GitHub", Run workflow. The optional inputs are the release version (default: the
version without `.pre`) and the next development version (default: next minor version, with `.pre`).

Or locally, from a clean `main` branch, with the [GitHub CLI](https://cli.github.com/) authenticated:

```shell
bundle exec rake release:run
bundle exec rake 'release:run[0.1.0,0.2.0]'
DRY_RUN=1 bundle exec rake release:run
```

`release:run`:

1. Checks the branch, the clean working tree, the absence of the tag, and runs `rake` (tests and RuboCop).
1. Removes `.pre` from the version, replaces the title and the date in `CHANGELOG.md`.
1. Builds the gem in `pkg/`, commits "Release v<version>", creates the tag `v<version>` and pushes them.
1. Creates the GitHub release, with the section of the changelog as notes, and the gem as attachment.
1. Sets the next `.pre` version, adds a new section to `CHANGELOG.md`, commits and pushes.

The push of the tag starts the workflow `deploy.yml`, which publishes the gem on rubygems.org.

### Workflows

| Workflow | Trigger | Role |
| --- | --- | --- |
| `test.yml` | Push on `main`, pull request | `rake` (tests, coverage and RuboCop) on Ruby 3.2 to 4.0 and macOS, the gem checks itself, `bundler-audit`, YARD check, build and install of the gem. |
| `release.yml` | Manual | Runs `rake release:run`. |
| `deploy.yml` | Tag `v*` | Checks that the tag is the version of the gem, and pushes it to rubygems.org. |

The actions are pinned by commit SHA (the version is in the comment) and updated by Dependabot (`.github/dependabot.yml`).

### One-time setup

- Secret `RELEASE_TOKEN` of the GitHub repository: personal access token with write access to the contents of the
  repository. A tag pushed with the default `GITHUB_TOKEN` does not trigger `deploy.yml`.
- Environment `rubygems` in the settings of the GitHub repository.
- Trusted publisher on rubygems.org (no API key to store, and it works with `rubygems_mfa_required`): for the first
  release, create a pending publisher at <https://rubygems.org/profile/oidc/pending_trusted_publishers> with the
  repository `laurent-martin/ruby-require-hygiene`, the workflow `deploy.yml` and the environment `rubygems`. Later,
  the same settings are in the page of the gem.

### Withdraw a version

`bundle exec rake release:yank[0.1.0]` (one-time password required), and describe the reason in the changelog.

The gem contains the library, the executable, `LICENSE`, the Markdown files of `docs/` and the root `*.md` files. The
PDF files are not in the gem.

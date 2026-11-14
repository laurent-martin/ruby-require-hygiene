# frozen_string_literal: true

require_relative 'lib/require_hygiene/version'

Gem::Specification.new do |spec|
  spec.name        = 'require_hygiene'
  spec.version     = RequireHygiene::VERSION
  spec.authors     = ['Laurent Martin']
  spec.email       = ['laurent.martin.l@gmail.com']
  spec.summary     = 'Static analysis of missing and unused `require` in Ruby files'
  spec.description = 'Finds, at the level of each Ruby file, the likely missing and the likely unused `require` and ' \
    '`require_relative`, with explained, confidence-rated diagnostics. Use it as a library or with the require_hygiene command.'
  spec.homepage    = 'https://github.com/laurent-martin/ruby-require-hygiene'
  spec.license     = 'Apache-2.0'
  spec.required_ruby_version = '>= 3.2'

  spec.metadata['homepage_uri']          = spec.homepage
  spec.metadata['changelog_uri']         = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['documentation_uri']     = "#{spec.homepage}/blob/main/docs/manual.md"
  spec.metadata['source_code_uri']       = "#{spec.homepage}/tree/main"
  spec.metadata['bug_tracker_uri']       = "#{spec.homepage}/issues"
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['allowed_push_host']     = 'https://rubygems.org'

  # Files of the gem: library, executable and the Markdown documentation, not the generated PDF files
  spec.files = Dir['lib/**/*.rb', 'bin/*', 'docs/*.md', '*.md', 'LICENSE'].reject { |f| File.directory?(f) }
  spec.bindir        = 'bin'
  spec.executables   = ['require_hygiene']
  spec.require_paths = ['lib']

  spec.add_dependency 'prism', '>= 1.0', '< 3'
  spec.add_dependency 'thor', '~> 1.3'
  # `rubydex` (semantic backend, experimental) is added with the missing-require rule, see docs/specification.md
end

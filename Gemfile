# frozen_string_literal: true

source 'https://rubygems.org'

# Runtime dependencies are in require_hygiene.gemspec
gemspec

group :development do
  gem 'minitest', '~> 6.0'
  gem 'bundler-audit', '~> 0.9'
  gem 'rake', '~> 13.0'
  # rubocop-shopify requires Ruby 3.3: on Ruby 3.2 only the tests run
  if RUBY_VERSION >= '3.3'
    gem 'rubocop', '~> 1.75'
    gem 'rubocop-performance', '~> 1.10'
    gem 'rubocop-shopify', '~> 3.1'
  end
  gem 'simplecov', '~> 0.22', require: false
  gem 'yard', '~> 0.9'
end

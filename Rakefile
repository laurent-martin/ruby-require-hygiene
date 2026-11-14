# frozen_string_literal: true

# Tasks: `rake -T`. Gem tasks (build, install, release) come from Bundler, documentation tasks from rakelib/doc.rake.
require 'bundler/gem_tasks'
require 'rake/testtask'
require 'yard'
require 'yard/rake/yardoc_task'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test' << 'lib'
  t.test_files = FileList['test/**/*_test.rb']
  t.warning = true
end

desc 'Lint with RuboCop'
task :rubocop do
  sh 'bundle', 'exec', 'rubocop'
end

# API documentation in doc/ (configuration in .yardopts)
YARD::Rake::YardocTask.new(:yard)

namespace :yard do
  desc 'Generate the API documentation, fail on warning'
  task :check do
    sh 'bundle', 'exec', 'yard', 'doc', '--fail-on-warning', '--no-save', '--no-stats', '--quiet', '--output-dir', 'tmp/yard'
  end
end

task default: %i[test rubocop]

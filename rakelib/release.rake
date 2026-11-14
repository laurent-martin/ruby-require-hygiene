# frozen_string_literal: true

# Release management, see "Release" in docs/development.md
#
# Development versions end with `.pre` (e.g. `0.2.0.pre`). `rake release:run` removes the suffix, commits, tags, creates the
# GitHub release, then starts the next development cycle. The tag triggers the GitHub workflow `deploy.yml` that pushes the
# gem to rubygems.org.

require 'date'
require 'tmpdir'
require_relative '../lib/require_hygiene/version'

namespace :release do
  GEM_NAME = 'require_hygiene'
  PRE_SUFFIX = '.pre'
  DATE_PLACE_HOLDER = 'Released: [Place date of release here]'
  VERSION_FILE = File.expand_path('../lib/require_hygiene/version.rb', __dir__)
  CHANGELOG_FILE = File.expand_path('../CHANGELOG.md', __dir__)
  VERSION_FORMAT = /\A\d+\.\d+\.\d+\z/
  RELEASE_BRANCH = 'main'

  # @return [Hash<Symbol,String>] Versions: :current, :release, :tag, :next_dev
  def release_versions(release_version, next_version)
    current = RequireHygiene::VERSION
    release = release_version.to_s.empty? ? current.delete_suffix(PRE_SUFFIX) : release_version
    abort "Invalid release version: #{release}" unless VERSION_FORMAT.match?(release)
    if next_version.to_s.empty?
      major, minor, _patch = release.split('.').map(&:to_i)
      next_version = [major, minor + 1, 0].join('.')
    end
    abort "Invalid next version: #{next_version}" unless VERSION_FORMAT.match?(next_version)
    {current: current, release: release, tag: "v#{release}", next_dev: "#{next_version}#{PRE_SUFFIX}"}
  end

  # @return [String] Changelog of the latest version, without its heading and release date, to use as release notes
  def latest_changelog
    section = File.read(CHANGELOG_FILE)[/^## .+?(?=^## |\z)/m] || abort('No version section in CHANGELOG.md')
    section.sub(/\A## .+\n+Released: .+\n*/, '').strip.gsub(/^### /, '## ')
  end

  def update_version_file(version)
    content = File.read(VERSION_FILE).sub(/VERSION = '[^']+'/, "VERSION = '#{version}'")
    File.write(VERSION_FILE, content)
  end

  # Replace the heading of the development version with the release version, and the date placeholder with today
  def update_changelog_for_release(current, release)
    content = File.read(CHANGELOG_FILE)
    abort "Missing section '## #{current}' in CHANGELOG.md" unless content.include?("\n## #{current}\n")
    abort "Missing '#{DATE_PLACE_HOLDER}' in CHANGELOG.md" unless content.include?(DATE_PLACE_HOLDER)
    content = content.sub("\n## #{current}\n", "\n## #{release}\n").sub(DATE_PLACE_HOLDER, "Released: #{Date.today.strftime('%Y-%m-%d')}")
    File.write(CHANGELOG_FILE, content)
  end

  # Add an empty section for the next development version, before the section of the release
  def add_next_changelog_section(next_dev)
    section = "\n## #{next_dev}\n\n#{DATE_PLACE_HOLDER}\n\n### New\n\n### Fixed\n\n"
    File.write(CHANGELOG_FILE, File.read(CHANGELOG_FILE).sub("\n## ", "#{section}## "))
  end

  def git_output(*args)
    IO.popen(['git', *args], &:read).strip
  end

  desc 'Create a release: rake release:run[version,next_version], env DRY_RUN=1 only shows the plan'
  task :run, %i[version next_version] do |_t, args|
    versions = release_versions(args[:version], args[:next_version])
    abort "Current version must end with #{PRE_SUFFIX}: #{versions[:current]}" unless versions[:current].end_with?(PRE_SUFFIX)
    puts "Current version:      #{versions[:current]}"
    puts "Release version:      #{versions[:release]} (tag #{versions[:tag]})"
    puts "Next development:     #{versions[:next_dev]}"
    next puts('Dry run: nothing changed') if ENV.key?('DRY_RUN')

    branch = git_output('branch', '--show-current')
    abort "Release from branch #{RELEASE_BRANCH}, not #{branch}" unless branch == RELEASE_BRANCH
    status = git_output('status', '--porcelain')
    abort "Git working tree not clean:\n#{status}" unless status.empty?
    sh 'gh', 'auth', 'status'
    abort "Tag #{versions[:tag]} already exists" unless git_output('tag', '--list', versions[:tag]).empty?

    # Same checks as the CI: tests and lint
    Rake::Task[:default].invoke

    update_version_file(versions[:release])
    update_changelog_for_release(versions[:current], versions[:release])
    notes_file = File.join(Dir.tmpdir, "#{GEM_NAME}_release_notes.md")
    File.write(notes_file, latest_changelog)

    # Build in a new process: this one has loaded the previous version
    gem_file = File.join('pkg', "#{GEM_NAME}-#{versions[:release]}.gem")
    mkdir_p 'pkg'
    sh 'gem', 'build', "#{GEM_NAME}.gemspec", '--output', gem_file

    sh 'git', 'add', VERSION_FILE, CHANGELOG_FILE
    sh 'git', 'commit', '-m', "Release #{versions[:tag]}"
    sh 'git', 'tag', '-a', versions[:tag], '-m', "Version #{versions[:release]}"
    # The tag triggers the workflow deploy.yml: the gem is pushed to rubygems.org
    sh 'git', 'push', 'origin', RELEASE_BRANCH, versions[:tag]
    sh 'gh', 'release', 'create', versions[:tag], '--title', "#{GEM_NAME} #{versions[:tag]}", '--notes-file', notes_file, gem_file

    update_version_file(versions[:next_dev])
    add_next_changelog_section(versions[:next_dev])
    sh 'git', 'add', VERSION_FILE, CHANGELOG_FILE
    sh 'git', 'commit', '-m', "Prepare for next development cycle (#{versions[:next_dev]})"
    sh 'git', 'push', 'origin', RELEASE_BRANCH
    puts "Release #{versions[:release]} done"
  end

  desc 'Yank a version from rubygems.org: rake release:yank[version] (asks for the one-time password)'
  task :yank, [:version] do |_t, args|
    abort 'Usage: rake release:yank[1.2.3]' if args[:version].to_s.empty?
    sh 'gem', 'yank', GEM_NAME, '--version', args[:version]
  end
end

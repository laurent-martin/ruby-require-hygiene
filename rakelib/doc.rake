# frozen_string_literal: true

# Documentation: Markdown files of docs/ and README.md, converted to PDF with gfm2pdf-toolchain, see docs/development.md
# Requires the env var GFM2PDF_HOME, the folder of https://github.com/laurent-martin/gfm2pdf-toolchain

require 'bundler'
require 'rake/clean'
require 'rbconfig'
require 'tmpdir'

namespace :doc do
  # Markdown files that make the manual, in the order of the PDF files. README.md is not converted: it only links.
  DOC_SOURCES = FileList['docs/*.md']
  # Folder of the generated PDF files, ignored by git
  DOC_PDF = DOC_SOURCES.ext('.pdf')

  # @return [String] Path of the gfm2pdf-toolchain script
  def gfm2pdf_script
    home = ENV.fetch('GFM2PDF_HOME') { abort 'Set GFM2PDF_HOME to the folder of gfm2pdf-toolchain, see docs/development.md' }
    script = File.join(home, 'lib', 'pandoc.rb')
    abort "Not found: #{script}" unless File.file?(script)
    script
  end

  # Run the toolchain outside the bundle of this project: it is an independent tool with its own requirements
  def toolchain(env = {}, *args)
    Bundler.with_unbundled_env { sh(env, RbConfig.ruby, gfm2pdf_script, *args) }
  end

  # @param mode [String] `build`, or `check`: a warning is an error
  def convert(source, target, mode: 'build')
    toolchain({'GFM2PDF_MODE' => mode}, 'pdf', source, target)
  end

  DOC_SOURCES.each do |source|
    file source.ext('.pdf') => [source] do |t|
      convert(source, t.name, mode: ENV.fetch('GFM2PDF_MODE', 'build'))
    end
  end

  desc 'Generate the PDF files of docs/*.md (env var GFM2PDF_HOME, optional GFM2PDF_ENGINE=latex|typst)'
  task pdf: DOC_PDF

  desc 'Check the Markdown files as CI: a warning or a broken internal link is an error (no PDF kept)'
  task :check do
    DOC_SOURCES.each do |source|
      toolchain({}, 'check-anchors', source)
      Dir.mktmpdir { |dir| convert(source, File.join(dir, 'check.pdf'), mode: 'check') }
    end
  end

  desc 'Renumber figures in docs/*.md (modifies the files, review with git diff)'
  task :renumber do
    DOC_SOURCES.each { |source| toolchain({}, 'renumber-figures', source) }
  end

  CLEAN.include(DOC_PDF)
end

desc 'Generate the PDF documentation (alias of doc:pdf)'
task doc: 'doc:pdf'

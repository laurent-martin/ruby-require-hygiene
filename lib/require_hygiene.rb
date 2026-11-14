# frozen_string_literal: true

# Library entry point of the `require` hygiene analysis, see docs/specification.md.
# It only requires the other files (a facade). It does not load the command line (Thor): use `require 'require_hygiene/cli'` for that.
require_relative 'require_hygiene/version'
require_relative 'require_hygiene/errors'
require_relative 'require_hygiene/configuration'
require_relative 'require_hygiene/require_directive'
require_relative 'require_hygiene/source_scanner'
require_relative 'require_hygiene/runtime_snapshot'
require_relative 'require_hygiene/isolation_check'
require_relative 'require_hygiene/baseline'
require_relative 'require_hygiene/checker'
require_relative 'require_hygiene/diagnostic'
require_relative 'require_hygiene/report'
require_relative 'require_hygiene/analyzer'

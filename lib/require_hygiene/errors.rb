# frozen_string_literal: true

module RequireHygiene
  # Base class of all errors raised by the gem: the library raises, only the CLI prints and exits
  class Error < StandardError; end

  # Invalid or unreadable configuration
  class ConfigurationError < Error; end
end

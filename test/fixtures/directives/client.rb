require 'set'
require "net/http" if defined?(Net)

begin
  require 'optional_backend'
rescue LoadError
  nil
end

name = 'adapter'
require name
require "adapters/#{name}"
send(:require, name)
obj.require 'not_kernel'

module Sample
  class Client
    def lazy
      require 'lazy_lib'
    end
  end
end

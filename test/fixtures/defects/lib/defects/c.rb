require 'defects/a'
require 'defects/a'
require 'defects/b'

module Defects
  # A is used, but `defects/a` is required twice: duplicate. B is required and never used: unused.
  # D is defined in `defects/d`, which is not required here: missing.
  class C
    DEFAULT = D.new
    def run = A.new
  end
end

# frozen_string_literal: true

require 'etc'

module RequireHygiene
  # Parallel execution of independent sub-process jobs
  module Workers
    # Maximum number of threads
    MAX_THREADS = 8

    class << self
      # @param items [Array] Jobs
      # @yieldparam item [Object] One job
      # @return [Array] Results, in the order of the items
      def map(items)
        results = Array.new(items.size)
        queue = Queue.new
        items.each_with_index { |item, index| queue << [item, index] }
        Array.new([[Etc.nprocessors, MAX_THREADS].min, 1].max) do
          Thread.new do
            loop do
              item, index = begin
                queue.pop(true)
              rescue ThreadError
                break
              end
              results[index] = yield(item)
            end
          end
        end.each(&:join)
        results
      end
    end
  end
end

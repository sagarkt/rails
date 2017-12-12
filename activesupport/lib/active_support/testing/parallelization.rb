# frozen_string_literal: true

require 'drb'
require 'drb/unix'
require 'tempfile'

module ActiveSupport
  module Testing
    class Parallelization
      class Server
        include DRb::DRbUndumped

        def initialize
          @queue = Queue.new
        end

        def record(reporter, result)
          reporter.synchronize do
            reporter.record(result)
          end
        end

        def << o; @queue << o; end

        def pop; @queue.pop; end
      end

      @after_fork_hooks = []

      def self.after_fork_hook(&blk)
        @after_fork_hooks << blk
      end

      def self.after_fork_hooks
        @after_fork_hooks
      end

      def initialize(queue_size)
        @queue_size  = queue_size
        @queue       = Server.new
        @url         = "drbunix://#{file}"
        @pool        = []

        DRb.start_service(@url, @queue)
      end

      def file
        File.join(Dir.tmpdir, Dir::Tmpname.make_tmpname('tests', 'fd'))
      end

      def after_fork(i)
        self.class.after_fork_hooks.each do |cb|
          cb.call i
        end
      end

      def start
        @pool = @queue_size.times.map { |i|
          fork {
            DRb.stop_service
            after_fork(i)

            queue = DRbObject.new_with_uri @url
            while job = queue.pop
              klass    = job[0]
              method   = job[1]
              reporter = job[2]
              result = Minitest.run_one_method klass, method
              result.failures = result.failures.map { |error|
                assertion = Minitest::Assertion.new error.message
                assertion.set_backtrace error.backtrace
                assertion
              }

              queue.record reporter, result
            end

            # We should also call the strategy object here for cleanup.
          }
        }
      end

      def << work
        @queue << work
      end

      def shutdown
        @queue_size.times { @queue << nil }
        @pool.each { |pid| Process.waitpid pid }
      end
    end
  end
end

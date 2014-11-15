
require 'pork/stat'

module Pork
  class Executor
    singleton_class.module_eval do
      attr_reader :stat

      def copy  desc=:default, &suite
        @stash[desc] = suite
      end
      def paste desc=:default, *args
        module_exec(*args, &search_stash(desc))
      end

      def before &block; @tests << [:before, block]; end
      def after  &block; @tests << [:after , block]; end

      def describe desc=:default, &suite
        executor = Class.new(self){ init("#{desc}: ") }
        executor.module_eval(&suite)
        @tests << [:describe, executor]
      end

      def would desc=:default, &test
        @tests << [:would, desc, test]
      end

      def expect *args, &block
        Expect.new(self, *args, &block)
      end

      def execute stat=Stat.new
        thread = Thread.current
        original_group, group = thread.group, ThreadGroup.new
        group.add(thread)
        thread[:pork_executor] = self
        stat.start
        execute_with_parent(stat)
      ensure
        original_group.add(thread)
      end

      private
      def init desc=''
        @desc, @tests, @stash, @before, @after = desc, [], {}, [], []
        @super_executor = ancestors[1..-1].find{ |a| a <= Executor }
      end

      def run desc, test
        assertions = stat.assertions
        context = new(desc)
        run_before(context)
        context.instance_eval(&test)
        if assertions == stat.assertions
          raise Error.new('Missing assertions')
        end
      rescue Error, StandardError => e
        case e
        when Skip
          stat.incr_skips
        when Failure
          stat.add_failure(e, description_for("would #{desc}"))
        when Error, StandardError
          stat.add_error(  e, description_for("would #{desc}"))
        end
      else
        print '.'
      ensure
        stat.incr_tests
        run_after(context)
      end

      protected
      def execute_with_parent stat=Stat.new
        @stat = stat
        @tests.each do |(type, arg, test)|
          case type
          when :before
            @before << arg
          when :after
            @after  << arg
          when :describe
            arg.execute_with_parent(stat)
          when :would
            run(arg, test)
          end
        end
      end

      def search_stash desc
        @stash[desc] or @super_executor && @super_executor.search_stash(desc)
      end

      def run_before context
        @super_executor && @super_executor.run_before(context)
        @before.each{ |b| context.instance_eval(&b) }
      end

      def run_after context
        @super_executor && @super_executor.run_after(context)
        @after.each{ |b| context.instance_eval(&b) }
      end

      def description_for name=''
        "#{@desc}#{@super_executor && @super_executor.description_for}#{name}"
      end
    end

    init

    def initialize desc
      @__pork__desc__ = desc
    end

    def skip
     raise Skip.new("Skipping #{@__pork__desc__}")
    end

    def flunk reason='Flunked'
      raise Error.new(reason)
    end

    def ok
      self.class.stat.incr_assertions
    end
  end
end

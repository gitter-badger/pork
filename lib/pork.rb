
require 'pork/executor'

module Pork
  module API
    module_function
    def before &block; Executor.before(&block); end
    def after  &block; Executor.after( &block); end
    def copy     desc=:default, &block; Executor.copy(    desc, &block); end
    def paste    desc=:default, *args ; Executor.paste(   desc, *args ); end
    def describe desc=:default, &suite; Executor.describe(desc, &suite); end
    def would    desc=:default, &test ; Executor.would(   desc, &test ); end
  end

  # default to :shuffled while eliminating warnings for uninitialized ivar
  def self.execute_mode mode=nil
    @execute_mode = mode || @execute_mode ||= :shuffled
  end

  def self.report_mode mode=nil
    @report_mode = mode || @report_mode ||= :dot
    require "pork/reporter/#{@report_mode}"
    @report_mode
  end

  def self.reporter_class
    const_get(report_mode.to_s.capitalize)
  end

  def self.reporter_extensions
    @reporter_extensions ||= []
  end

  def self.Rainbows!
    require 'pork/extra/rainbows'
    reporter_extensions << Rainbows
  end

  def self.show_source
    require 'pork/extra/show_source'
    reporter_extensions << ShowSource
  end

  def self.stat
    @stat ||= Pork::Stat.new
  end

  def self.seed
    @seed ||= if Random.const_defined?(:DEFAULT)
                Random::DEFAULT.seed
              else
                Thread.current.randomizer.seed # Rubinius (rbx)
              end
  end

  def self.trap sig='SIGINT'
    Signal.trap(sig) do
      stat.report
      puts "\nterminated by signal #{sig}"
      exit 255
    end
  end

  def self.execute
    Random.srand(ENV['PORK_SEED'].to_i) if ENV['PORK_SEED']
    seed
    if ENV['PORK_TEST']
      require 'pork/mode/shuffled'
      if tests = Executor[ENV['PORK_TEST']]
        paths, imps =
          tests.group_by{ |p| p.kind_of?(Array) }.values_at(true, false)
        @stat = Executor.execute(execute_mode, stat, paths) if paths
        @stat = imps.inject(stat){ |s, i| i.execute(execute_mode, s) } if imps
      else
        puts "Cannot find test: #{ENV['PORK_TEST']}"
        exit 254
      end
    else
      @stat = Executor.execute(execute_mode, stat)
    end
  end

  def self.run
    execute_mode(ENV['PORK_MODE'])
    report_mode(ENV['PORK_REPORT'])
    trap
    execute
    stat.report
  end

  def self.autorun auto=true
    @auto = auto
    @autorun ||= at_exit do
      next unless @auto
      run
      exit stat.failures + stat.errors + ($! && 1).to_i
    end
  end
end

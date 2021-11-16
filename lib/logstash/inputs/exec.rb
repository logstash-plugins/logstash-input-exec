# encoding: utf-8
require "logstash/inputs/base"
require "logstash/namespace"
require "socket" # for Socket.gethostname
require "stud/interval"
require "rufus/scheduler"

require 'logstash/plugin_mixins/ecs_compatibility_support'

# Periodically run a shell command and capture the whole output as an event.
#
# Notes:
#
# * The `command` field of this event will be the command run.
# * The `message` field of this event will be the entire stdout of the command.
#
class LogStash::Inputs::Exec < LogStash::Inputs::Base

  include LogStash::PluginMixins::ECSCompatibilitySupport(:disabled, :v1, :v8 => :v1)

  config_name "exec"

  default :codec, "plain"

  # Command to run. For example : `uptime`
  config :command, :validate => :string, :required => true

  # Interval to run the command. Value is in seconds.
  # Either `interval` or `schedule` option must be defined.
  config :interval, :validate => :number

  # Schedule of when to periodically run command, in Cron format
  # For example: "* * * * *" (execute command every minute, on the minute)
  # Either `interval` or `schedule` option must be defined.
  config :schedule, :validate => :string

  def register
    @hostname = Socket.gethostname.freeze
    @io       = nil
    
    if (@interval.nil? && @schedule.nil?) || (@interval && @schedule)
      raise LogStash::ConfigurationError, "exec input: either 'interval' or 'schedule' option must be defined."
    end

    @host_name_field =            ecs_select[disabled: 'host',                     v1: '[host][name]']
    @process_command_line_field = ecs_select[disabled: 'command',                  v1: '[process][command_line]']
    @process_exit_code_field =    ecs_select[disabled: '[@metadata][exit_status]', v1: '[process][exit_code]']
    
    # migrate elapsed time tracking to whole nanos, from legacy floating-point fractional seconds
    @process_elapsed_time_field = ecs_select[disabled: nil,                        v1: '[@metadata][input][exec][process][elapsed_time]'] # in nanos
    @legacy_duration_field =      ecs_select[disabled: '[@metadata][duration]',    v1: nil] # in seconds
  end # def register

  def run(queue)
    if @schedule
      @scheduler = Rufus::Scheduler.new(:max_work_threads => 1)
      @scheduler.cron @schedule do
        execute(queue)
      end
      @scheduler.join
    else
      while !stop?
        duration = execute(queue)
        wait_until_end_of_interval(duration)
      end # loop
    end
  end # def run

  def stop
    close_io()
    @scheduler.shutdown(:wait) if @scheduler
  end

  # Execute a given command
  # @param queue the LS queue to append events to
  def execute(queue)
    start = Time.now
    output = exit_status = nil
    begin
      @logger.debug? && @logger.debug("Running exec", :command => @command)
      output, exit_status = run_command()
    rescue StandardError => e
      @logger.error("Error while running command",
        :command => @command, :exception => e, :backtrace => e.backtrace)
    rescue Exception => e
      @logger.error("Exception while running command",
        :command => @command, :exception => e, :backtrace => e.backtrace)
    end
    duration = Time.now.to_r - start.to_r
    @logger.debug? && @logger.debug("Command completed", :command => @command, :duration => duration.to_f)
    if output
      @codec.decode(output) do |event|
        decorate(event)
        event.set(@host_name_field, @hostname) unless event.include?(@host_name_field)
        event.set(@process_command_line_field, @command) unless event.include?(@process_command_line_field)
        event.set(@process_exit_code_field, exit_status) unless event.include?(@process_exit_code_field)
        event.set(@process_elapsed_time_field, to_nanos(duration)) if @process_elapsed_time_field
        event.set(@legacy_duration_field, duration.to_f) if @legacy_duration_field
        queue << event
      end
    end
    duration
  end

  private

  def run_command
    @io = IO.popen(@command)
    output = @io.read
    @io.close # required in order to read $?
    exit_status = $?.exitstatus
    [output, exit_status]
  ensure
    close_io()
  end

  # Close @io
  def close_io
    return if @io.nil? || @io.closed?
    @io.close
    @io = nil
  end

  # Wait until the end of the interval
  # @param duration [Integer] the duration of the last command executed
  def wait_until_end_of_interval(duration)
    # Sleep for the remainder of the interval, or 0 if the duration ran
    # longer than the interval.
    sleeptime = [0, @interval - duration].max
    if sleeptime > 0
      Stud.stoppable_sleep(sleeptime) { stop? }
    else
      @logger.warn("Execution ran longer than the interval. Skipping sleep.",
                   :command => @command, :duration => duration, :interval => @interval)
    end
  end

  # convert seconds to nanoseconds
  # @param time_diff [Numeric] the (rational value) difference to convert
  def to_nanos(time_diff)
    (time_diff * 1_000_000).to_i
  end

end # class LogStash::Inputs::Exec

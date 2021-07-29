# encoding: utf-8
require "timecop"
require "time"
require_relative "../spec_helper"
require "logstash/devutils/rspec/shared_examples"
require 'logstash/plugin_mixins/ecs_compatibility_support/spec_helper'

describe LogStash::Inputs::Exec, :ecs_compatibility_support do

  ecs_compatibility_matrix(:disabled, :v1, :v8) do |ecs_select|

    before(:each) do
      allow_any_instance_of(described_class).to receive(:ecs_compatibility).and_return(ecs_compatibility)
    end

    context "when register" do
      let(:input) { described_class.new("command" => "ls", "interval" => 0) }

      it "should not raise error if config is valid" do
        # register will try to load jars and raise if it cannot find jars or if org.apache.log4j.spi.LoggingEvent class is not present
        expect { input.register }.to_not raise_error
      end

      context "with an invalid config" do
        let(:input) { described_class.new("command" => "ls") }
        it "should raise error" do
          expect { input.register }.to raise_error(LogStash::ConfigurationError)
        end
      end
    end

    context "when operating normally" do
      let(:input) { described_class.new("command" => "echo 'hi!'", "interval" => 0) }
      let(:queue) { [] }

      before :each do
        input.register
      end

      it "enqueues some events" do
        expect(input.logger).not_to receive(:error)

        input.execute(queue)

        expect(queue.size).not_to be_zero
      end
    end

    context "when command fails" do
      let(:input) { described_class.new("command" => "non_existent", "interval" => 0) }
      let(:queue) { [] }

      before :each do
        input.register
      end

      it "enqueues some events" do
        expect(input.logger).to receive(:error)

        input.execute(queue)

        expect(queue.size).to be_zero
      end
    end

    context "when a command runs normally" do
      let(:command) { "/bin/sh -c 'sleep 1; /bin/echo -n two; exit 3'" }
      let(:input) { described_class.new("command" => command, "interval" => 0) }
      let(:queue) { [] }

      before do
        input.register
        input.execute(queue)
      end

      after do
        input.stop
      end

      it "has duration (in seconds)" do
        duration = queue.pop.get('[@metadata][duration]')
        expect(duration).to be > 1
        expect(duration).to be < 3
      end if ecs_select.active_mode == :disabled

      it "reports process elapsed time (in nanos)" do
        elapsed_time = queue.pop.get('[@metadata][input][exec][process][elapsed_time]')
        expect(elapsed_time).to be > 1 * 1_000_000
        expect(elapsed_time).to be < 3 * 1_000_000
      end if ecs_select.active_mode != :disabled
      
      it "has output as expected" do
        expect(queue.pop.get('message')).to eq "two"
      end

      it "reports process command_line  " do
        if ecs_select.active_mode == :disabled
          expect(queue.pop.get('command')).to eql command
        else
          expect(queue.pop.get('[process][command_line]')).to eql command
        end
      end

      it "reports process exit_code" do
        if ecs_select.active_mode == :disabled
          expect(queue.pop.get('[@metadata][exit_status]')).to eq 3
        else
          expect(queue.pop.get('[process][exit_code]')).to eq 3
        end
      end

    end

  end

  context "when scheduling" do
    let(:input) { described_class.new("command" => "ls --help", "schedule" => "* * * * * UTC") }
    let(:queue) { [] }

    before do
      input.register
    end

    it "should properly schedule" do
      Timecop.travel(Time.new(2000))
      Timecop.scale(60)
      runner = Thread.new do
        input.run(queue)
      end
      sleep 3
      input.stop
      runner.kill
      runner.join
      expect(queue.size).to eq(2)
      Timecop.return
    end
  end

  context "when interrupting the plugin" do

    it_behaves_like "an interruptible input plugin" do
      let(:config) { { "command" => "ls", "interval" => 0 } }
    end

    it_behaves_like "an interruptible input plugin" do
      let(:config) { { "command" => "ls", "interval" => 100 } }
    end

  end

end

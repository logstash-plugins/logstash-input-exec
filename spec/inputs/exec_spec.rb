# encoding: utf-8
require "timecop"
require "time"
require_relative "../spec_helper"

describe LogStash::Inputs::Exec do

  context "when register" do
    it "should not raise error if config is valid" do
      input = LogStash::Plugin.lookup("input", "exec").new("command" => "ls", "interval" => 0)
      # register will try to load jars and raise if it cannot find jars or if org.apache.log4j.spi.LoggingEvent class is not present
      expect {input.register}.to_not raise_error
    end
    it "should raise error if config is invalid" do
      input = LogStash::Plugin.lookup("input", "exec").new("command" => "ls")
      expect {input.register}.to raise_error
    end
  end

  context "when operating normally" do
    let(:input) { LogStash::Plugin.lookup("input", "exec").new("command" => "ls", "interval" => 0) }
    let(:queue) { [] }
    let(:loggr) { double('loggr') }

    before :each do
      expect(LogStash::Inputs::Exec).to receive(:logger).and_return(loggr).exactly(7).times
      allow(loggr).to receive(:info)
      allow(loggr).to receive(:info?)
      allow(loggr).to receive(:warn)
      allow(loggr).to receive(:warn?)
      allow(loggr).to receive(:debug)
      allow(loggr).to receive(:debug?)
    end

    it "enqueues some events" do
      input.register
      expect(loggr).not_to receive(:error)

      input.execute(queue)

      expect(queue.size).not_to be_zero
    end
  end

  context "when a command runs normally" do
    let(:input) { LogStash::Plugin.lookup("input", "exec").new("command" => "/bin/sh -c 'sleep 1; /bin/echo -n two; exit 3'", "interval" => 0) }
    let(:queue) { [] }

    before do
      input.register
      input.execute(queue)
    end

    it "has duration tracked" do
      expect(queue.pop.get('[@metadata][duration]')).to be > 1
    end
    it "has output as expected" do
      expect(queue[0].get('message')).to eq "two"
    end
    it "has exit_status tracked" do
      expect(queue[0].get('[@metadata][exit_status]')).to eq 3
    end

  end

  # context "when scheduling" do
  #   let(:input) { LogStash::Plugin.lookup("input", "exec").new("command" => "ls", "schedule" => "* * * * * UTC") }
  #   let(:queue) { [] }
  
  #   before do
  #     input.register
  #   end
  
  #   it "should properly schedule" do
  #     Timecop.travel(Time.new(2000))
  #     Timecop.scale(60)
  #     runner = Thread.new do
  #       input.run(queue)
  #     end
  #     sleep 3
  #     input.stop
  #     runner.kill
  #     runner.join
  #     expect(queue.size).to eq(2)
  #     Timecop.return
  #   end
  
  # end

  context "when interrupting the plugin" do

    it_behaves_like "an interruptible input plugin" do
      let(:config) { { "command" => "ls", "interval" => 0 } }
    end

    it_behaves_like "an interruptible input plugin" do
      let(:config) { { "command" => "ls", "interval" => 100 } }
    end

  end

end

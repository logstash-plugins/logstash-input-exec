# encoding: utf-8
require_relative "../spec_helper"

describe LogStash::Inputs::Exec do

  it "should register" do
    input = LogStash::Plugin.lookup("input", "exec").new("command" => "ls", "interval" => 0)

    # register will try to load jars and raise if it cannot find jars or if org.apache.log4j.spi.LoggingEvent class is not present
    expect {input.register}.to_not raise_error
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

      input.inner_run(queue)

      expect(queue.size).not_to be_zero
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

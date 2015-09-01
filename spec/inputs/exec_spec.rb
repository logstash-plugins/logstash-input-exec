# encoding: utf-8
require_relative "../spec_helper"

describe LogStash::Inputs::Exec do

  it "should register" do
    input = LogStash::Plugin.lookup("input", "exec").new("command" => "uptime", "interval" => 0)

    # register will try to load jars and raise if it cannot find jars or if org.apache.log4j.spi.LoggingEvent class is not present
    expect {input.register}.to_not raise_error
  end

  context "when interrupting the plugin" do

    it_behaves_like "an interruptible input plugin" do
      let(:config) { { "command" => "uptime", "interval" => 0 } }
    end

    it_behaves_like "an interruptible input plugin" do
      let(:config) { { "command" => "uptime", "interval" => 100 } }
    end

  end

end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe Forge::Providers::Response do
  it "converts tool calls to message format" do
    response = described_class.new(
      content: nil,
      tool_calls: [{ id: "tc1", name: "read_file", arguments: { "path" => "foo.rb" } }]
    )
    msg = response.to_message
    expect(msg[:role]).to eq("assistant")
    expect(msg[:tool_calls].first[:function][:name]).to eq("read_file")
  end
end

RSpec.describe Forge::Parallel::Executor do
  let(:config) { Forge::Configuration.new("/nonexistent/config.toml") }

  it "runs tasks in parallel" do
    executor = described_class.new(config)
    tasks = 4.times.map do |i|
      Forge::Parallel::Task.new(id: i, description: "task #{i}") { sleep(0.01); i * 2 }
    end
    executor.run_parallel(tasks)
    expect(tasks.map(&:result)).to eq([0, 2, 4, 6])
  end
end

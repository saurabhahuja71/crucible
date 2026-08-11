# frozen_string_literal: true

require "spec_helper"

RSpec.describe Forge::Agent::TodoStore do
  it "tracks and formats multi-step work" do
    store = described_class.new
    todo = store.add("inspect the project")
    expect(store.open_count).to eq(1)
    store.complete(todo.id)
    expect(store.format).to include("[x] 1. inspect the project")
  end
end

RSpec.describe Forge::Permissions::Manager do
  let(:config) { Forge::Configuration.new("/nonexistent/config.toml") }

  it "blocks capability tools in plan mode" do
    manager = described_class.new(config)
    manager.set_mode("plan")
    expect { manager.authorize!("shell_execute", { "command" => "ls" }) }.to raise_error(Forge::SafetyError)
  end

  it "supports one-time and permanent approvals" do
    config.data["permissions"]["path"] = File.join(Dir.mktmpdir, "permissions.json")
    manager = described_class.new(config, handler: ->(_request) { :always })
    expect(manager.authorize!("shell_execute", { "command" => "ls" })).to be true
    expect(manager.approvals.first).to include("shell_execute")
  end
end

RSpec.describe Forge::Tools::HttpRequest do
  let(:config) { Forge::Configuration.new("/nonexistent/config.toml") }
  let(:workspace) { Forge::Safety::Workspace.new(config, cwd: Dir.mktmpdir) }
  let(:sandbox) { Forge::Safety::Sandbox.new(config) }
  let(:tool) { described_class.new(workspace: workspace, sandbox: sandbox) }

  it "rejects unsupported methods and non-http URLs" do
    result = tool.call("method" => "delete", "url" => "file:///tmp/x")
    expect(result.success).to be false
    expect(result.error).to include("Only GET and POST")
  end
end

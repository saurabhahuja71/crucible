# frozen_string_literal: true

require "spec_helper"

RSpec.describe Forge::Configuration do
  it "loads defaults when no config file exists" do
    config = described_class.new("/nonexistent/config.toml")
    expect(config.fetch("providers.primary")).to eq("openai")
    expect(config.fetch("agent.max_turns")).to eq(50)
  end

  it "resolves environment variables" do
    ENV["TEST_FORGE_KEY"] = "secret123"
    config = described_class.new("/nonexistent/config.toml")
    result = config.resolve_env("${TEST_FORGE_KEY}")
    expect(result).to eq("secret123")
  ensure
    ENV.delete("TEST_FORGE_KEY")
  end

  describe ".default_allowed_commands" do
    it "includes common dev and container commands" do
      cmds = described_class.default_allowed_commands
      expect(cmds.size).to be >= 90
      %w[podman docker systemctl journalctl ssh sed awk curl tar rg git].each do |cmd|
        expect(cmds).to include(cmd)
      end
    end

    it "is used as default for safety and ssh allow-lists" do
      config = described_class.new("/nonexistent/config.toml")
      expect(config.fetch("safety.allowed_commands")).to eq(described_class.default_allowed_commands)
      expect(config.fetch("ssh.allowed_commands")).to eq(described_class.default_allowed_commands)
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe Forge::Tools::ReadFile do
  let(:tmpdir) { Dir.mktmpdir }
  let(:config) { Forge::Configuration.new("/nonexistent/config.toml") }
  let(:workspace) { Forge::Safety::Workspace.new(config, cwd: tmpdir) }
  let(:sandbox) { Forge::Safety::Sandbox.new(config) }
  let(:tool) { described_class.new(workspace: workspace, sandbox: sandbox) }

  after { FileUtils.remove_entry(tmpdir) }

  it "reads file contents with line numbers" do
    File.write(File.join(tmpdir, "hello.rb"), "puts 'hello'\nputs 'world'\n")
    result = tool.call({ "path" => "hello.rb" })
    expect(result.success).to be true
    expect(result.output).to include("1|puts 'hello'")
    expect(result.output).to include("2|puts 'world'")
  end
end

RSpec.describe Forge::Tools::EditFile do
  let(:tmpdir) { Dir.mktmpdir }
  let(:config) { Forge::Configuration.new("/nonexistent/config.toml") }
  let(:workspace) { Forge::Safety::Workspace.new(config, cwd: tmpdir) }
  let(:sandbox) { Forge::Safety::Sandbox.new(config) }
  let(:tool) { described_class.new(workspace: workspace, sandbox: sandbox) }

  after { FileUtils.remove_entry(tmpdir) }

  it "replaces unique strings surgically" do
    File.write(File.join(tmpdir, "app.rb"), "VERSION = '1.0.0'\n")
    result = tool.call({ "path" => "app.rb", "old_string" => "1.0.0", "new_string" => "2.0.0" })
    expect(result.success).to be true
    expect(File.read(File.join(tmpdir, "app.rb"))).to include("2.0.0")
  end
end

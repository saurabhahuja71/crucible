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

  it "pages large files when limit is omitted" do
    body = (1..250).map { |i| "line#{i}" }.join("\n") + "\n"
    File.write(File.join(tmpdir, "big.txt"), body)
    result = tool.call({ "path" => "big.txt" })
    expect(result.success).to be true
    expect(result.output).to include("lines=250")
    expect(result.output).to include("truncated")
    expect(result.output).to include("1|line1")
    expect(result.output).not_to include("250|line250")
  end
end

RSpec.describe Forge::Tools::ShellExecute do
  let(:tmpdir) { Dir.mktmpdir }
  let(:config) { Forge::Configuration.new("/nonexistent/config.toml") }
  let(:workspace) { Forge::Safety::Workspace.new(config, cwd: tmpdir) }
  let(:sandbox) { Forge::Safety::Sandbox.new(config) }
  let(:tool) { described_class.new(workspace: workspace, sandbox: sandbox) }

  after { FileUtils.remove_entry(tmpdir) }

  it "runs commands through a shell" do
    result = tool.call({ "command" => "ls -1" })
    expect(result.success).to be true
    expect(result.output).to include("exit=0")
  end
end

RSpec.describe Forge::Tools::SearchFiles do
  let(:tmpdir) { Dir.mktmpdir }
  let(:config) do
    cfg = Forge::Configuration.new("/nonexistent/config.toml")
    cfg.data["workspace"]["trust"] = true
    cfg
  end
  let(:workspace) { Forge::Safety::Workspace.new(config, cwd: tmpdir) }
  let(:sandbox) { Forge::Safety::Sandbox.new(config) }
  let(:tool) { described_class.new(workspace: workspace, sandbox: sandbox) }

  after { FileUtils.remove_entry(tmpdir) }

  it "searches a home path when trusted" do
    bashrc = File.expand_path("~/.bashrc")
    skip "no ~/.bashrc" unless File.file?(bashrc)

    result = tool.call({ "pattern" => "export", "path" => "~/.bashrc" })
    expect(result.success).to be true
    expect(result.output).to include("export")
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

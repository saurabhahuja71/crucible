# frozen_string_literal: true

require "spec_helper"

RSpec.describe Forge::UI::StatusBar do
  it "keeps status output within narrow terminal widths" do
    bar = described_class.new(theme: Forge::UI::Theme.new(color: false), width: 40)
    output = bar.render(provider: "ollama", model: "very-long-model-name", mode: "ask", workspace: "/tmp/cruks", todos: 2)
    expect(output.lines.all? { |line| line.chomp.length <= 40 }).to be true
  end
end

RSpec.describe Forge::UI::ToolView do
  it "renders compact semantic tool cards" do
    output = described_class.new.render("run_tests", { "command" => "bundle exec rspec" }, result: "ok", success: true)
    expect(output).to include("Run", "command: bundle exec rspec", "✓ passed")
    expect(output).not_to include("{\"command\"")
  end
end

RSpec.describe Forge::UI::Markdown do
  it "keeps code blocks visually distinct" do
    output = described_class.new.render("# Heading\n```ruby\nputs 'ok'\n```")
    expect(output).to include("Heading", "│ puts 'ok'")
  end
end

RSpec.describe Forge::UI::CompletionSummary do
  it "renders changed files and verification" do
    output = described_class.new.render("Finished", changed: ["M app.rb"], verification: ["✓ tests"])
    expect(output).to include("Done", "M app.rb", "✓ tests")
  end
end

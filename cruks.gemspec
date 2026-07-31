# frozen_string_literal: true

require_relative "lib/forge/version"

Gem::Specification.new do |spec|
  spec.name          = "cruks"
  spec.version       = Forge::VERSION
  spec.authors       = ["Cruks Contributors"]
  spec.email         = ["cruks@example.com"]

  spec.summary       = "Local-first terminal coding agent"
  spec.description   = "Production-quality Ruby CLI coding agent with LLM providers, tools, SSH, and parallel execution"
  spec.homepage      = "https://github.com/user/dboper/cruks"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.files = Dir.chdir(__dir__) do
  Dir.glob("{exe,lib}/**/*", File::FNM_DOTMATCH).select do |f|
      File.file?(f) && !f.end_with?(".gem")
    end + %w[cruks.gemspec README.md LICENSE config/cruks.sglang.toml config/cruks.example.toml scripts/cruks-sglang.sh]
  end
  spec.bindir        = "exe"
  spec.executables   = %w[cruks cruks-s]
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", "~> 2.9"
  spec.add_dependency "faraday-retry", "~> 2.2"
  spec.add_dependency "net-ssh", "~> 7.2"
  spec.add_dependency "pastel", "~> 0.8"
  spec.add_dependency "toml-rb", "~> 3.0"
  spec.add_dependency "tty-box", "~> 0.7"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "tty-spinner", "~> 0.9"
  spec.add_dependency "tty-table", "~> 0.12"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
end

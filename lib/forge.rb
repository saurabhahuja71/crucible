# frozen_string_literal: true

require "logger"
require "pathname"
require "time"

module Forge
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class ProviderError < Error; end
  class SafetyError < Error; end
  class ToolError < Error; end

  ROOT = Pathname(__dir__).join("..").expand_path.freeze
  CONFIG_DIR = Pathname(Dir.home).join(".config", "cruks").freeze
  DATA_DIR = Pathname(Dir.home).join(".local", "share", "cruks").freeze

  def self.logger
    @logger ||= Logger.new($stderr).tap do |log|
      log.level = Logger::INFO
      log.progname = "cruks"
    end
  end

  def self.logger=(logger)
    @logger = logger
  end
end

require_relative "forge/version"
require_relative "forge/configuration"
require_relative "forge/hooks"
require_relative "forge/permissions"
require_relative "forge/providers/base"
require_relative "forge/providers/openai_compatible"
require_relative "forge/providers/ollama"
require_relative "forge/providers/registry"
require_relative "forge/safety/command_validator"
require_relative "forge/safety/workspace"
require_relative "forge/tools/base"
require_relative "forge/tools/filesystem"
require_relative "forge/tools/shell"
require_relative "forge/tools/git"
require_relative "forge/tools/ssh_tools"
require_relative "forge/tools/advanced"
require_relative "forge/tools/builtin"
require_relative "forge/agent/loop"
require_relative "forge/agent/todos"
require_relative "forge/parallel/executor"
require_relative "forge/ssh/manager"
require_relative "forge/debug/integration"
require_relative "forge/mcp/client"
require_relative "forge/skills/loader"
require_relative "forge/runtime"
require_relative "forge/ui/terminal"
require_relative "forge/tui/app"
require_relative "forge/cli"

# frozen_string_literal: true

require "toml-rb"
require "fileutils"
require "json"

module Forge
  class Configuration
    def self.default_allowed_commands
      %w[
        awk basename bundle bzip2 cal cargo cat chmod chown cmp comm cp curl cut
        date df diff dig dirname docker du env file find free gcc g++ gem git go
        groups gunzip gzip head helm hostname id ifconfig ip irb java javac
        journalctl kill killall kubectl ld less ln locate ls lsblk lsof make mkdir
        mount mv mvn nano nc netstat nice ninja node nohup npm npx pgrep ping
        pip pip3 podman printf ps pkill python python3 rake readlink realpath rg rm
        rmdir rsync ruby rustc rustup scp sed sftp sort source ss ssh stat systemctl
        tail tar tee test timeout top touch traceroute tr type umount uniq uname unzip
        uptime watch wc wget whereis which whoami xargs xz yarn zip
      ].freeze
    end

    def self.default_system_prompt
      <<~PROMPT.strip
        You are Cruks, an expert software engineering agent. You help users write, debug,
        refactor, and understand code. Use available tools to inspect the codebase, run
        commands, and make precise edits. Be concise, accurate, and safety-conscious.
        Prefer surgical changes over large rewrites. Always explain your reasoning.
      PROMPT
    end

    DEFAULTS = {
      "workspace" => {
        "trust" => false,
        "auto_approve" => false
      },
      "agent" => {
        "max_turns" => 50,
        "summarize_after_messages" => 40,
        "system_prompt" => default_system_prompt
      },
      "providers" => {
        "primary" => "openai",
        "failover" => [],
        "openai" => {
          "type" => "openai_compatible",
          "api_key" => "${OPENAI_API_KEY}",
          "base_url" => "https://api.openai.com/v1",
          "model" => "gpt-4o",
          "temperature" => 0.2,
          "max_tokens" => 8192,
          "timeout" => 120
        },
        "ollama" => {
          "type" => "ollama",
          "base_url" => "http://localhost:11434",
          "model" => "llama3.2",
          "temperature" => 0.2,
          "max_tokens" => 8192,
          "timeout" => 300
        }
      },
      "safety" => {
        "sandbox_shell" => true,
        "allowed_commands" => default_allowed_commands,
        "blocked_paths" => ["/etc", "/usr", "/bin", "/sbin", "/var"],
        "confirm_destructive" => true
      },
      "ssh" => {
        "config_path" => "~/.config/cruks/ssh_hosts.toml",
        "default_timeout" => 30,
        "allowed_commands" => default_allowed_commands
      },
      "parallel" => {
        "max_workers" => 4,
        "isolation" => "thread"
      },
      "logging" => {
        "level" => "info",
        "audit_path" => "~/.local/share/cruks/audit.log"
      },
      "mcp" => {
        "servers" => []
      }
    }.freeze

    attr_reader :data, :path

    def self.load(path = nil)
      path ||= discover_config_path
      new(path)
    end

    def self.discover_config_path
      candidates = [
        Pathname(Dir.pwd).join("cruks.toml"),
        CONFIG_DIR.join("config.toml")
      ]
      candidates.find(&:exist?) || CONFIG_DIR.join("config.toml")
    end

    def initialize(path)
      @path = Pathname(path)
      @data = deep_merge(DEFAULTS, load_file)
      ensure_directories!
    end

    def [](key)
      fetch(key)
    end

    def fetch(key, default = nil)
      keys = key.to_s.split(".")
      result = keys.reduce(@data) { |h, k| h.is_a?(Hash) ? h[k] : nil }
      result.nil? ? default : result
    end

    def provider(name = nil)
      name ||= fetch("providers.primary")
      providers = fetch("providers")
      config = providers[name]
      raise ConfigurationError, "Unknown provider: #{name}" unless config

      { "name" => name, **config }
    end

    def failover_providers
      primary = fetch("providers.primary")
      names = [primary] + Array(fetch("providers.failover"))
      names.map { |n| provider(n) }.uniq { |p| p["name"] }
    end

    def resolve_env(value)
      return value unless value.is_a?(String)

      value.gsub(/\$\{(\w+)\}/) do
        ENV.fetch(Regexp.last_match(1), "")
      end
    end

    def expand_path(value)
      Pathname(value.to_s.sub(/\A~/, Dir.home)).expand_path
    end

    private

    def load_file
      return {} unless @path.exist?

      TomlRB.load_file(@path.to_s)
    rescue TomlRB::ParseError => e
      raise ConfigurationError, "Invalid config at #{@path}: #{e.message}"
    end

    def ensure_directories!
      CONFIG_DIR.mkpath
      DATA_DIR.mkpath
      (DATA_DIR / "sessions").mkpath
    end

    def deep_merge(base, override)
      base.merge(override) do |_key, old_val, new_val|
        if old_val.is_a?(Hash) && new_val.is_a?(Hash)
          deep_merge(old_val, new_val)
        else
          new_val
        end
      end
    end
  end
end

# frozen_string_literal: true

module Forge
  class CLI
    def self.run(argv)
      new.run(argv)
    end

    def run(argv)
      opts, args = parse_options(argv)

      case args[0]
      when "exec"
        headless(args[1..], opts)
      when "sessions"
        list_sessions
      when "version", "-v", "--version"
        puts "cruks #{Forge::VERSION}"
      when "init"
        init_config
      when "help", "-h", "--help", nil
        print_help
      else
        interactive(args, opts)
      end
    end

    private

    def parse_options(argv)
      opts = { config: nil, model: nil, trust: false }
      remaining = argv.dup

      while remaining.any?
        case remaining[0]
        when "-c", "--config"
          opts[:config] = remaining[1]
          remaining.shift(2)
        when "-m", "--model"
          opts[:model] = remaining[1]
          remaining.shift(2)
        when "--trust"
          opts[:trust] = true
          remaining.shift
        else
          break
        end
      end

      [opts, remaining]
    end

    def build_runtime(opts)
      Runtime.new(
        config_path: opts[:config],
        model: opts[:model],
        trust: opts[:trust]
      )
    end

    def interactive(argv, opts)
      runtime = build_runtime(opts)
      TUI::App.new(runtime).run
    end

    def headless(args, opts)
      task = args.reject { |a| a.start_with?("--") }.join(" ")
      abort "Usage: cruks exec \"task description\"" if task.empty?

      runtime = build_runtime(opts)
      result = runtime.exec(task, stream: true)
      puts result
    end

    def list_sessions
      sessions = Agent::Session.list
      if sessions.empty?
        puts "No saved sessions."
        return
      end

      sessions.each do |s|
        puts "#{s[:id]}  #{s[:message_count]} messages  #{s[:created_at]}"
      end
    end

    def init_config
      dest = Forge::CONFIG_DIR.join("config.toml")
      example = Forge::ROOT.join("config", "forge.example.toml")
      if dest.exist?
        puts "Config already exists: #{dest}"
        return
      end

      Forge::CONFIG_DIR.mkpath
      FileUtils.cp(example, dest)
      puts "Created config at #{dest}"
      puts "Edit the file and set your API keys."
    end

    def print_help
      puts <<~HELP
        Cruks v#{Forge::VERSION} — Local-first terminal coding agent (Ruby)

        Usage:
          cruks / forge           Start interactive TUI session
          cruks exec "task"       Run a single task (headless)
          cruks sessions          List saved sessions
          cruks init              Create default config
          cruks version           Show version

        Options:
          -c, --config PATH       Path to config TOML file
          -m, --model NAME        Override model for primary provider
          --trust                 Trust workspace without prompt

        SGLang shortcut:
          cruks-s                 Interactive session via SGLang (:30000)
          cruks-s exec "task"       Headless via SGLang

        Environment:
          OPENAI_API_KEY          API key for OpenAI-compatible providers

        Documentation: https://github.com/user/dboper/cruks
      HELP
    end
  end
end

require "fileutils"

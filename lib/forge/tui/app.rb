# frozen_string_literal: true

require "pastel"
require "tty-box"
require "tty-prompt"
require "tty-spinner"
require "tty-table"

module Forge
  module TUI
    class Renderer
      def initialize
        @pastel = Pastel.new
      end

      def banner
        TTY::Box.frame(
          "Cruks v#{Forge::VERSION}\nLocal-first coding agent",
          title: { top_left: " ⚒ ", bottom_right: " ⚒ " },
          border: :thick,
          padding: [1, 2]
        )
      end

      def assistant(content)
        $stdout.puts @pastel.green("▸ Assistant:")
        $stdout.puts wrap(content)
        $stdout.puts
      end

      def stream_chunk(chunk)
        $stdout.print @pastel.dim(chunk)
        $stdout.flush
      end

      def stream_end
        $stdout.puts
        $stdout.puts
      end

      def tool_start(name, arguments)
        args_preview = arguments.is_a?(Hash) ? arguments.inspect[0, 80] : arguments.to_s[0, 80]
        $stdout.puts @pastel.yellow("  ⚙ #{name}") + @pastel.dim(" #{args_preview}")
      end

      def tool_end(name, output, success:)
        icon = success ? "✓" : "✗"
        color = success ? :cyan : :red
        $stdout.puts @pastel.public_send(color, "  #{icon} #{name}") + @pastel.dim(" → #{output}")
      end

      def error(message)
        $stdout.puts @pastel.red("✗ Error: #{message}")
      end

      def info(message)
        $stdout.puts @pastel.blue("ℹ #{message}")
      end

      def table(headers, rows)
        $stdout.puts TTY::Table.new(header: headers, rows: rows).render
      end

      private

      def wrap(text, width: 100)
        text.to_s.lines.map { |line| line.chomp }.join("\n")
      end
    end

    class SlashCommands
      COMMANDS = %w[help model tools ssh parallel debug clear resume skills trust auto exit quit].freeze

      def initialize(app)
        @app = app
        @handlers = {
          "help" => method(:cmd_help),
          "model" => method(:cmd_model),
          "tools" => method(:cmd_tools),
          "ssh" => method(:cmd_ssh),
          "parallel" => method(:cmd_parallel),
          "debug" => method(:cmd_debug),
          "clear" => method(:cmd_clear),
          "resume" => method(:cmd_resume),
          "skills" => method(:cmd_skills),
          "trust" => method(:cmd_trust),
          "auto" => method(:cmd_auto),
          "exit" => method(:cmd_exit),
          "quit" => method(:cmd_exit)
        }
      end

      def handle(input)
        parts = input.split(/\s+/, 2)
        cmd = parts[0].delete_prefix("/").downcase
        args = parts[1]

        handler = @handlers[cmd]
        return { handled: false } unless handler

        { handled: true, result: handler.call(args) }
      end

      private

      def cmd_help(_args)
        <<~HELP
          Slash commands:
            /help              Show this help
            /model [name]      Show or switch provider/model
            /tools             List available tools
            /ssh [list|connect <name>]  SSH host management
            /parallel <tasks>  Run parallel sub-agents (semicolon-separated)
            /debug [on|off]    Toggle debug mode
            /clear             Clear screen
            /resume [id]       List or resume sessions
            /skills            List loaded skills
            /trust             Trust current workspace
            /auto [on|off]     Toggle auto-approve mode
            /exit              Exit Forge
        HELP
      end

      def cmd_model(args)
        if args && !args.empty?
          @app.switch_provider(args)
        else
          provider = @app.current_provider
          "Provider: #{provider.name} | Model: #{provider.model}"
        end
      end

      def cmd_tools(_args)
        @app.tool_names.join(", ")
      end

      def cmd_ssh(args)
        parts = (args || "list").split(/\s+/)
        case parts[0]
        when "list"
          hosts = @app.ssh_hosts
          return "No SSH hosts configured" if hosts.empty?

          hosts.map { |h| "#{h.name}: #{h.user}@#{h.host}:#{h.port}" }.join("\n")
        when "connect"
          name = parts[1]
          return "Usage: /ssh connect <name>" unless name

          @app.ssh_connect(name)
          "Connected to #{name}"
        else
          "Usage: /ssh list|connect <name>"
        end
      end

      def cmd_parallel(args)
        return "Usage: /parallel task1; task2; task3" unless args

        tasks = args.split(";").map(&:strip).reject(&:empty?)
        @app.run_parallel(tasks)
      end

      def cmd_debug(args)
        case args
        when "on" then @app.debug_mode = true; "Debug mode enabled"
        when "off" then @app.debug_mode = false; "Debug mode disabled"
        else "Debug mode: #{@app.debug_mode? ? 'on' : 'off'}"
        end
      end

      def cmd_clear(_args)
        system("clear") || print("\e[2J\e[H")
        nil
      end

      def cmd_resume(args)
        if args && !args.empty?
          @app.resume_session(args)
          "Resumed session #{args}"
        else
          sessions = Agent::Session.list
          return "No saved sessions" if sessions.empty?

          sessions.map { |s| "#{s[:id][0..7]}… (#{s[:message_count]} msgs)" }.join("\n")
        end
      end

      def cmd_skills(_args)
        skills = @app.skill_names
        skills.empty? ? "No skills loaded" : skills.join(", ")
      end

      def cmd_trust(_args)
        @app.trust_workspace!
        "Workspace trusted. Destructive actions may proceed without confirmation."
      end

      def cmd_auto(args)
        case args
        when "on" then @app.auto_approve = true; "Auto-approve enabled ⚠"
        when "off" then @app.auto_approve = false; "Auto-approve disabled"
        else "Auto-approve: #{@app.auto_approve? ? 'on ⚠' : 'off'}"
        end
      end

      def cmd_exit(_args)
        :exit
      end
    end

    class App
      attr_accessor :debug_mode, :auto_approve
      attr_reader :runtime

      def initialize(runtime)
        @runtime = runtime
        @renderer = Renderer.new
        @slash = SlashCommands.new(self)
        @prompt = TTY::Prompt.new
        @debug_mode = false
        @auto_approve = runtime.workspace.auto_approve
      end

      def run
        $stdout.puts @renderer.banner
        @renderer.info("Workspace: #{runtime.workspace.root}")
        @renderer.info("Provider: #{current_provider.name} (#{current_provider.model})")
        @renderer.info("Type /help for commands. Ctrl+C to interrupt.\n")

        loop do
          input = @prompt.read_line(@prompt_message)
          break if input.nil?

          input = input.strip
          next if input.empty?

          if input.start_with?("/")
            result = @slash.handle(input)
            next unless result[:handled]

            if result[:result] == :exit
              @renderer.info("Goodbye!")
              break
            end

            $stdout.puts result[:result] if result[:result].is_a?(String)
            next
          end

          run_agent(input)
        rescue Interrupt
          @renderer.info("\nInterrupted. Type /exit to quit.")
        rescue StandardError => e
          @renderer.error("#{e.class}: #{e.message}")
          Forge.logger.error(e.full_message) if debug_mode?
        end
      end

      def current_provider
        runtime.provider_chain.primary
      end

      def tool_names
        runtime.tools.names
      end

      def skill_names
        runtime.skills.map { |s| s.respond_to?(:name) ? s.name : s.class.name }
      end

      def ssh_hosts
        runtime.ssh_manager.list_hosts
      end

      def ssh_connect(name)
        runtime.ssh_manager.connect(name)
      end

      def switch_provider(name)
        runtime.switch_provider(name)
      end

      def trust_workspace!
        runtime.workspace.instance_variable_set(:@trusted, true)
      end

      def auto_approve?
        @auto_approve
      end

      def debug_mode?
        @debug_mode
      end

      def resume_session(id)
        runtime.resume_session(id)
      end

      def run_parallel(task_descriptions)
        results = runtime.run_parallel_agents(task_descriptions) do |event, task|
          case event
          when :start
            @renderer.info("Parallel: starting #{task.description[0, 50]}")
          when :complete
            @renderer.info("Parallel: completed #{task.description[0, 50]}")
          when :failed
            @renderer.error("Parallel: failed #{task.description[0, 50]}")
          end
        end
        results.map.with_index { |r, i| "Task #{i + 1}: #{r.to_s[0, 200]}" }.join("\n")
      end

      private

      def prompt_message
        "cruks> "
      end

      def run_agent(input)
        streaming = false
        runtime.agent_loop.on_event = lambda do |event, data|
          case event
          when :content
            @renderer.stream_chunk(data) unless streaming
            streaming = true
          when :assistant_message
            if streaming
              @renderer.stream_end
              streaming = false
            else
              @renderer.assistant(data[:content])
            end
          when :tool_start
            @renderer.tool_start(data[:name], data[:arguments])
          when :tool_end
            @renderer.tool_end(data[:name], data[:output], success: data[:success])
          end
        end

        runtime.agent_loop.run(input, stream: true)
      end
    end
  end
end

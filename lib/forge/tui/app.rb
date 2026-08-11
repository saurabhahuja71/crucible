# frozen_string_literal: true

require "pastel"
require "reline"
require "tty-box"
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
        $stdout.puts @pastel.green.bold("▸ Assistant:")
        # Default terminal foreground (same contrast as user input) — never dim.
        $stdout.puts wrap(content)
        $stdout.puts
      end

      def stream_chunk(chunk)
        # Stream answers in normal terminal color so they match prompt/question contrast.
        $stdout.print chunk
        $stdout.flush
      end

      def stream_end
        $stdout.puts
        $stdout.puts
      end

      def tool_start(name, arguments)
        args_preview = arguments.is_a?(Hash) ? arguments.inspect[0, 80] : arguments.to_s[0, 80]
        $stdout.puts @pastel.yellow("  ⚙ #{name}") + " #{args_preview}"
      end

      def tool_end(name, output, success:)
        icon = success ? "✓" : "✗"
        color = success ? :cyan : :red
        text = output.to_s
        preview_limit = 4000
        if text.length > preview_limit
          text = "#{text[0, preview_limit]}\n… (#{text.length - preview_limit} more chars truncated in TUI)"
        end
        $stdout.puts @pastel.public_send(color, "  #{icon} #{name}")
        # Tool body in default color (readable); indent only for hierarchy.
        text.each_line { |line| $stdout.puts "    #{line.chomp}" }
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
      COMMANDS = %w[help model mode theme todo queue tools ssh parallel debug clear resume skills trust auto permissions new exit quit].freeze

      def initialize(app)
        @app = app
        @handlers = {
          "help" => method(:cmd_help),
          "model" => method(:cmd_model),
          "mode" => method(:cmd_mode),
          "theme" => method(:cmd_theme),
          "todo" => method(:cmd_todo),
          "queue" => method(:cmd_queue),
          "tools" => method(:cmd_tools),
          "ssh" => method(:cmd_ssh),
          "parallel" => method(:cmd_parallel),
          "debug" => method(:cmd_debug),
          "clear" => method(:cmd_clear),
          "resume" => method(:cmd_resume),
          "skills" => method(:cmd_skills),
          "trust" => method(:cmd_trust),
          "auto" => method(:cmd_auto),
          "permissions" => method(:cmd_permissions),
          "new" => method(:cmd_new),
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
            /mode ask|allow|plan  Change permission mode
            /theme dark|light  Change display theme preference
            /todo [clear]      Show or clear live todos
            /queue             Show queued work
            /tools             List available tools
            /ssh [list|connect <name>]  SSH host management
            /parallel <tasks>  Run parallel sub-agents (semicolon-separated)
            /debug [on|off]    Toggle debug mode
            /clear             Clear screen
            /resume [id]       List or resume sessions
            /skills            List loaded skills
            /trust             Trust current workspace
            /auto [on|off]     Toggle auto-approve mode
            /permissions       List permanent approvals
            /new               Start a fresh session
            /exit              Exit Cruks
        HELP
      end

      def cmd_model(args)
        if args && !args.empty?
          name = args.split.first
          if @app.provider_names.include?(name)
            @app.switch_provider(name)
          else
            @app.switch_model(name)
          end
          "Model: #{@app.current_provider.model}"
        else
          provider = @app.current_provider
          models = @app.available_models
          "Provider: #{provider.name} | Model: #{provider.model}#{models.empty? ? '' : " | Available: #{models.join(', ')}"}"
        end
      end

      def cmd_mode(args)
        return "Permission mode: #{@app.permission_mode}" unless args && !args.empty?

        @app.set_permission_mode(args.split.first)
        "Permission mode: #{@app.permission_mode}"
      end

      def cmd_theme(args)
        return "Theme: #{@app.theme}" unless args && !args.empty?

        @app.theme = args.split.first
        "Theme: #{@app.theme}"
      end

      def cmd_todo(args)
        return @app.todo_summary unless args && !args.empty?

        case args.split.first
        when "clear" then @app.clear_todos; "Todos cleared"
        else "Usage: /todo [clear]"
        end
      end

      def cmd_queue(_args)
        "Queued prompts: 0 (interactive input is processed serially)"
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
        when "on" then @app.auto_approve = true; @app.set_permission_mode("allow"); "Auto-approve enabled ⚠"
        when "off" then @app.auto_approve = false; @app.set_permission_mode("ask"); "Auto-approve disabled"
        else "Auto-approve: #{@app.auto_approve? ? 'on ⚠' : 'off'}"
        end
      end

      def cmd_permissions(args)
        if args&.start_with?("remove ")
          key = args.delete_prefix("remove ")
          return @app.remove_permission(key) ? "Approval removed" : "Approval not found"
        end
        approvals = @app.permission_approvals
        approvals.empty? ? "No permanent approvals" : approvals.join("\n")
      end

      def cmd_new(_args)
        @app.new_session
        "Started a new session"
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
        @debug_mode = false
        @auto_approve = runtime.workspace.auto_approve
        runtime.permissions.handler = method(:request_permission)
      end

      def run
        $stdout.puts @renderer.banner
        @renderer.info("Workspace: #{runtime.workspace.root}")
        @renderer.info("Provider: #{current_provider.name} (#{current_provider.model})")
        @renderer.info("Type /help for commands. Ctrl+C to interrupt.\n")

        loop do
          input = read_user_input
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
          $stdout.puts
          @renderer.info("Interrupted. Type /exit to quit.")
        rescue StandardError => e
          @renderer.error("#{e.class}: #{e.message}")
          if debug_mode? || ENV["CRUKS_DEBUG"]
            $stderr.puts e.full_message
          else
            Forge.logger.error(e.full_message)
          end
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

      def permission_mode
        runtime.permissions.mode
      end

      def set_permission_mode(mode)
        runtime.set_permission_mode(mode)
      end

      def theme
        @theme ||= runtime.config.fetch("theme", "dark")
      end

      def theme=(value)
        value = value.to_s.downcase
        raise ConfigurationError, "Theme must be dark or light" unless %w[dark light].include?(value)

        @theme = value
      end

      def todo_summary
        Agent::TODO_STORE.format
      end

      def clear_todos
        Agent::TODO_STORE.clear
      end

      def permission_approvals
        runtime.permissions.approvals
      end

      def remove_permission(key)
        runtime.permissions.remove(key)
      end

      def new_session
        runtime.new_session
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

      def switch_model(name)
        runtime.switch_model(name)
      end

      def available_models
        runtime.available_models
      end

      def provider_names
        runtime.config.fetch("providers").keys - %w[primary failover]
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

      def read_user_input
        if $stdin.tty?
          Reline.readline(prompt_message, true)
        else
          $stdout.print(prompt_message)
          $stdin.gets
        end
      end

      def run_agent(input)
        streaming = false
        streamed_content = +""
        runtime.agent_loop.on_event = lambda do |event, data|
          case event
          when :content
            chunk = data.to_s
            next if chunk.empty?

            streamed_content << chunk
            @renderer.stream_chunk(chunk)
            streaming = true
          when :assistant_message
            content = data[:content].to_s
            if streaming
              @renderer.stream_end
              streaming = false
            elsif !content.empty?
              @renderer.assistant(content)
            end
          when :tool_start
            if streaming
              @renderer.stream_end
              streaming = false
              streamed_content.clear
            end
            @renderer.tool_start(data[:name], data[:arguments])
          when :tool_end
            @renderer.tool_end(data[:name], data[:output], success: data[:success])
          end
        end

        runtime.agent_loop.run(input, stream: true)
      end

      def request_permission(request)
        $stdout.puts "\nPermission required: #{request.tool_name} #{request.arguments.inspect}"
        $stdout.print "Allow once [y], always [a], deny [n]? "
        answer = $stdin.gets.to_s.strip.downcase
        answer == "a" ? :always : answer == "y"
      end
    end
  end
end

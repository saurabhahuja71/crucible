# frozen_string_literal: true

require "pastel"
require "reline"
require "tty-box"
require "tty-spinner"
require "tty-table"
require "shellwords"

module Forge
  module TUI
    class Renderer
      def initialize(color: true, debug: false)
        @theme = UI::Theme.new(color: color)
        @pastel = Pastel.new(enabled: color)
        @status = UI::StatusBar.new(theme: @theme)
        @activity = UI::Activity.new(theme: @theme)
        @tool_view = UI::ToolView.new(theme: @theme)
        @markdown = UI::Markdown.new(theme: @theme)
        @debug = debug
        @transcript = []
        @scroll_offset = 0
        @mouse_enabled = false
      end

      attr_reader :mouse_enabled

      def banner
        TTY::Box.frame("⚒ Cruks v#{Forge::VERSION}\nLocal-first coding agent",
                       border: :thick, padding: [1, 2])
      end

      def startup(provider:, model:, workspace:, context: nil)
        lines = [@theme.bold("⚒ Cruks #{Forge::VERSION}"), @theme.dim("Local-first coding agent"), "",
                 "  #{@theme.paint(:success, '✓')} #{provider}",
                 "  #{@theme.paint(:success, '✓')} #{model}"]
        lines << "  #{@theme.paint(:success, '✓')} Context #{context}" if context
        lines.concat(["", "  #{@theme.dim(workspace.to_s)}"])
        $stdout.puts lines.join("\n")
      end

      def assistant(content)
        record("Assistant", content)
        $stdout.puts @theme.bold("\n#{@theme.paint(:model, 'Cruks')}")
        # Default terminal foreground (same contrast as user input) — never dim.
        $stdout.puts @markdown.render(content)
        $stdout.puts
      end

      def stream_chunk(chunk)
        @activity.finish
        # Stream answers in normal terminal color so they match prompt/question contrast.
        $stdout.print chunk
        $stdout.flush
      end

      def stream_end
        $stdout.puts
        $stdout.puts
      end

      def stream_finished(content)
        @activity.finish
        record("Assistant", content)
        stream_end
      end

      def tool_start(name, arguments)
        @activity.update(tool_label(name, arguments))
        @active_tool = name
        @active_tool_arguments = arguments
        @active_tool_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def tool_end(name, output, success:)
        @activity.finish
        record("Error: #{name}", output.to_s.lines.first.to_s.strip) unless success
        duration = if @active_tool_started_at
                     (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @active_tool_started_at).round(1)
                   end
        $stdout.puts @tool_view.render(name, @active_tool_arguments || {}, result: output,
                                       success: success, duration: duration)
      end

      def error(message)
        @activity.finish
        $stdout.puts @pastel.red("╭─ Error ─╮\n│ #{message}\n╰─────────╯")
      end

      def info(message)
        $stdout.puts @pastel.blue("ℹ #{message}")
      end

      def footer(provider:, model:, mode:, todos:)
        mouse = @mouse_enabled ? "mouse:on" : "mouse:off"
        $stdout.puts @status.render(provider: provider, model: model, mode: mode,
                                    workspace: @workspace || ".", todos: todos)
        $stdout.puts @theme.dim("  MODE: #{mode.to_s.upcase} · Ctrl-T permissions · Ctrl-Y todos · /help · #{mouse}")
      end

      def todo_panel(items)
        completed = items.count(&:completed)
        $stdout.puts @theme.bold("Tasks")
        if items.empty?
          $stdout.puts @theme.dim("  No active tasks · /todo add <description>")
          return
        end

        items.each do |item|
          marker = item.completed ? @theme.paint(:success, "✓") : @theme.paint(:info, "○")
          $stdout.puts "  #{marker} #{item.description}"
        end
        $stdout.puts @theme.dim("  Progress: #{completed}/#{items.length} complete")
      end

      def workspace=(path)
        @workspace = path
      end

      def thinking
        @activity.start("Thinking...")
      end

      def set_mouse(enabled)
        @mouse_enabled = enabled
        $stdout.print(enabled ? "\e[?1000h\e[?1006h" : "\e[?1000l\e[?1006l")
        $stdout.flush
        enabled
      end

      def scroll(direction = "bottom")
        return "No transcript yet" if @transcript.empty?

        height = viewport_height
        max_offset = [@transcript.length - height, 0].max
        case direction.to_s.downcase
        when "up", "back", "pageup" then @scroll_offset = [@scroll_offset - height, 0].max
        when "down", "forward", "pagedown" then @scroll_offset = [@scroll_offset + height, max_offset].min
        when "top", "home" then @scroll_offset = 0
        else @scroll_offset = max_offset
        end
        visible = @transcript[@scroll_offset, height] || []
        $stdout.puts @pastel.dim("\nTranscript #{@scroll_offset + 1}-#{@scroll_offset + visible.length}/#{@transcript.length}")
        visible.each_with_index do |line, index|
          marker = scrollbar_marker(@scroll_offset + index, @transcript.length, height)
          $stdout.puts "#{line} #{marker}"
        end
        "Scroll #{direction}: #{@scroll_offset + 1}-#{@scroll_offset + visible.length}/#{@transcript.length} (use /scroll up|down|top|bottom)"
      end

      def table(headers, rows)
        $stdout.puts TTY::Table.new(header: headers, rows: rows).render
      end

      def completion(summary, changed: [], verification: [])
        $stdout.puts UI::CompletionSummary.new(theme: @theme).render(summary, changed: changed, verification: verification)
      end

      def tool_label(name, arguments)
        case name.to_s
        when "search_files", "search_symbols" then "Searching repository..."
        when "read_file", "file_info" then "Reading #{arguments['path']}..."
        when "edit_file", "write_file", "apply_patch" then "Editing files..."
        when "run_tests", "shell_execute" then "Running command..."
        else "Running #{name}..."
        end
      end

      private

      def record(label, content)
        content.to_s.lines.each { |line| @transcript << "#{label}: #{line.chomp}" }
        @scroll_offset = [@transcript.length - viewport_height, 0].max
      end

      def viewport_height
        [(ENV.fetch("LINES", "24").to_i - 8), 5].max
      end

      def scrollbar_marker(index, total, height)
        return "│" if total <= height

        thumb = [[(index.to_f / total * height).floor, 0].max, height - 1].min
        index % height == thumb ? "█" : "│"
      end

      def wrap(text, width: 100)
        text.to_s.lines.map { |line| line.chomp }.join("\n")
      end
    end

    class SlashCommands
      COMMANDS = %w[help model mode theme todo queue tools ssh parallel debug clear scroll mouse status doctor changes diff logs history resume sessions skills trust auto permissions new exit quit].freeze

      def initialize(app)
        @app = app
        @handlers = {
          "help" => method(:cmd_help),
          "model" => method(:cmd_model),
          "mode" => method(:cmd_mode),
          "theme" => method(:cmd_theme),
          "todo" => method(:cmd_todo),
          "scroll" => method(:cmd_scroll),
          "mouse" => method(:cmd_mouse),
          "status" => method(:cmd_status),
          "doctor" => method(:cmd_doctor),
          "changes" => method(:cmd_changes),
          "diff" => method(:cmd_diff),
          "logs" => method(:cmd_logs),
          "history" => method(:cmd_history),
          "sessions" => method(:cmd_sessions),
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
            /todo [add|done|clear|on|off|toggle]  Manage/show the live todo list
            /scroll up|down|top|bottom  Scroll long output
            /mouse on|off      Toggle terminal mouse reporting
            /status            Show current session status
            /doctor            Diagnose the local environment
            /changes           Show changed files
            /diff              Show current diff
            /logs              Show recent diagnostics
            /history           Show conversation history
            /sessions          List saved sessions
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
            /permissions [ask|allow|plan|toggle]  Permission controls/list approvals
            Ctrl-T              Toggle ASK/ALLOW permission mode
            Ctrl-Y              Toggle todo panel visibility
            /new               Start a fresh session
            /exit              Exit Cruks
        HELP
      end

      def cmd_model(args)
        if args && !args.empty?
          name = args.split.first
          return "'#{name}' is a permission mode; use /mode #{name}" if %w[ask allow plan].include?(name)
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

        mode = args.split.first
        @app.set_permission_mode(mode)
        @app.mode_announcement(mode)
      end

      def cmd_theme(args)
        return "Theme: #{@app.theme}" unless args && !args.empty?

        @app.theme = args.split.first
        "Theme: #{@app.theme}"
      end

      def cmd_todo(args)
        return @app.todo_summary unless args && !args.empty?

        parts = args.split(/\s+/, 2)
        case parts.first
        when "on", "off", "toggle"
          @app.set_todo_visibility(parts.first)
          "Todo panel: #{@app.todo_visible? ? 'on' : 'off'}"
        when "add"
          return "Usage: /todo add description" if parts[1].to_s.strip.empty?

          @app.add_todo(parts[1]); @app.todo_summary
        when "done", "complete"
          return "Usage: /todo done ID" unless parts[1]

          @app.complete_todo(parts[1]); @app.todo_summary
        when "clear" then @app.clear_todos; "Todos cleared"
        else "Usage: /todo [add description|done ID|clear|on|off|toggle]"
        end
      end

      def cmd_scroll(args)
        @app.scroll_output(args || "bottom")
      end

      def cmd_mouse(args)
        return "Mouse: #{@app.mouse_enabled? ? 'on' : 'off'}" unless args

        @app.set_mouse(args.split.first)
        "Mouse reporting: #{@app.mouse_enabled? ? 'on' : 'off'}"
      end

      def cmd_status(_args)
        @app.status_summary
      end

      def cmd_doctor(_args)
        @app.doctor_summary
      end

      def cmd_changes(_args)
        @app.changes_summary
      end

      def cmd_diff(_args)
        @app.current_diff
      end

      def cmd_logs(_args)
        @app.recent_logs
      end

      def cmd_history(_args)
        @app.history_summary
      end

      def cmd_sessions(_args)
        sessions = Agent::Session.list
        sessions.empty? ? "No saved sessions" : sessions.map { |s| "#{s[:id][0, 8]}  #{s[:message_count]} messages  #{s[:created_at]}" }.join("\n")
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
        value = args.to_s.downcase
        if %w[ask allow plan].include?(value)
          @app.set_permission_mode(value)
          return @app.mode_announcement(value)
        end
        if value == "toggle" || %w[on off].include?(value)
          next_mode = value == "off" || (value == "toggle" && @app.permission_mode == "allow") ? "ask" : "allow"
          @app.set_permission_mode(next_mode)
          return @app.mode_announcement(next_mode)
        end
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

      def initialize(runtime, color: true, debug: false)
        @runtime = runtime
        @renderer = Renderer.new(color: color, debug: debug)
        @slash = SlashCommands.new(self)
        @debug_mode = false
        @auto_approve = runtime.workspace.auto_approve
        @mouse_enabled = false
        @todo_visible = true
        install_keybindings
        @renderer.workspace = runtime.workspace.root
        @initial_worktree_files = current_worktree_files
        runtime.permissions.handler = method(:request_permission)
      end

      def run
        @renderer.startup(provider: current_provider.name, model: current_provider.model,
                          workspace: runtime.workspace.root, context: context_size)
        @renderer.info("MODE: #{permission_mode.upcase} · /mode ask|allow|plan · /permissions toggle · /auto on|off")
        @renderer.info("/help commands · /todo · /changes · /diff · /status · /doctor · /scroll · /mouse on|off · /quit")
        @renderer.info("Ctrl+C interrupts; Ctrl+D or /quit exits. Mouse is off by default; enable with /mouse on.\n")

        loop do
          @renderer.footer(provider: current_provider.name, model: current_provider.model,
                           mode: permission_mode, todos: (@todo_visible ? Agent::TODO_STORE.open_count : "off"))
          @renderer.todo_panel(Agent::TODO_STORE.items) if @todo_visible
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
      ensure
        @renderer.set_mouse(false) if @mouse_enabled
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

      def mode_announcement(mode)
        case mode.to_s
        when "plan" then "Plan mode enabled\n\nCruks will inspect the repository and propose changes without modifying files."
        when "allow" then "Allow mode enabled\n\nApproved tool actions can execute without repeated confirmation."
        else "Ask mode enabled\n\nCruks will request approval for capability tools."
        end
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
        return "Todo panel is off (use /todo on or Ctrl-Y)" unless @todo_visible

        Agent::TODO_STORE.format
      end

      def set_todo_visibility(value)
        @todo_visible = case value.to_s.downcase
                        when "on" then true
                        when "off" then false
                        else !@todo_visible
                        end
      end

      def todo_visible?
        @todo_visible
      end

      def status_summary
        <<~STATUS
          Cruks Status

            Model       #{current_provider.model}
            Provider    #{current_provider.name}
            Mode        #{permission_mode.upcase}
            Workspace   #{runtime.workspace.root}
            Context     #{context_size || 'unavailable'}
            Tasks       #{todo_progress}
            Changes     #{changed_files.length} files
        STATUS
      end

      def doctor_summary
        checks = {
          "Ollama/provider configured" => !current_provider.nil?,
          "Workspace accessible" => runtime.workspace.root.directory?,
          "Git available" => system("command -v git >/dev/null 2>&1"),
          "Ruby available" => system("command -v ruby >/dev/null 2>&1")
        }
        "Cruks Doctor\n\n" + checks.map { |label, ok| "  #{ok ? '✓' : '✗'} #{label}" }.join("\n") +
          "\n\n  Model\n    #{current_provider.model}\n  Workspace\n    #{runtime.workspace.root}"
      end

      def changed_files
        current_worktree_files - Array(@initial_worktree_files)
      end

      def current_worktree_files
        output = `git -C #{Shellwords.escape(runtime.workspace.root.to_s)} status --short 2>/dev/null`
        output.lines.filter_map do |line|
          path = line[3..].to_s.strip
          next if path.empty?

          "#{line[0, 2].strip} #{path}".strip
        end
      end

      def changes_summary
        files = changed_files
        files.empty? ? "Changes\n\n  Working tree clean" : "Changes\n\n" + files.map { |file| "  #{file}" }.join("\n")
      end

      def current_diff
        output = `git -C #{Shellwords.escape(runtime.workspace.root.to_s)} diff 2>/dev/null`
        output.empty? ? "No unstaged diff" : output
      end

      def recent_logs
        path = runtime.config.expand_path(runtime.config.fetch("logging.audit_path").to_s)
        path.file? ? "Recent diagnostics\n\n#{path.readlines.last(20).join}" : "No diagnostics available"
      end

      def history_summary
        messages = runtime.agent_loop.session.messages.last(12)
        messages.empty? ? "No conversation history" : messages.map { |m| "#{m['role'] || m[:role]}: #{(m['content'] || m[:content]).to_s.lines.first.to_s.strip}" }.join("\n")
      end

      def todo_progress
        items = Agent::TODO_STORE.items
        items.empty? ? "0/0 complete" : "#{items.count(&:completed)}/#{items.length} complete"
      end

      def context_size
        value = runtime.config.fetch("providers.#{runtime.config.fetch('providers.primary')}.context")
        value ? "#{value} tokens" : nil
      end

      def clear_todos
        Agent::TODO_STORE.clear
      end

      def add_todo(description)
        Agent::TODO_STORE.add(description)
      end

      def complete_todo(id)
        Agent::TODO_STORE.complete(id)
      end

      def set_mouse(value)
        normalized = value.to_s.downcase
        raise ConfigurationError, "Mouse must be on or off" unless %w[on off].include?(normalized)

        @mouse_enabled = normalized == "on"
        @renderer.set_mouse(@mouse_enabled)
      end

      def mouse_enabled?
        @mouse_enabled
      end

      def scroll_output(direction)
        @renderer.scroll(direction)
      end

      def install_keybindings
        return unless Reline.respond_to?(:core)

        unless Reline::LineEditor.method_defined?(:cruks_toggle_permission)
          Reline::LineEditor.class_eval do
            def cruks_toggle_permission(_key = nil)
              set_current_line("/permissions toggle", "/permissions toggle".bytesize)
              send(:ed_newline, nil)
            end

            def cruks_toggle_todos(_key = nil)
              set_current_line("/todo toggle", "/todo toggle".bytesize)
              send(:ed_newline, nil)
            end
          end
        end
        config = Reline.core.config
        %i[emacs vi_insert vi_command].each do |keymap|
          config.add_default_key_binding_by_keymap(keymap, [20], :cruks_toggle_permission)
          config.add_default_key_binding_by_keymap(keymap, [25], :cruks_toggle_todos)
        end
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
        "cruks ❯ "
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
        @renderer.thinking
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
              @renderer.stream_finished(streamed_content)
              streaming = false
            elsif !content.empty?
              @renderer.assistant(content)
            end
          when :tool_start
            if streaming
              @renderer.stream_finished(streamed_content)
              streaming = false
              streamed_content.clear
            end
            @renderer.tool_start(data[:name], data[:arguments])
          when :tool_end
            @renderer.tool_end(data[:name], data[:output], success: data[:success])
          end
        end

        result = runtime.agent_loop.run(input, stream: true)
        @renderer.completion(result, changed: changed_files.map { |file| "M #{file}" })
      end

      def request_permission(request)
        command = request.arguments["command"] || request.arguments.inspect
        dangerous = command.to_s.match?(/\brm\b|\bmv\b|\bchmod\b|\bdelete\b/i)
        title = dangerous ? "⚠ Destructive command" : "Command requires approval"
        $stdout.puts "\n╭─ #{title} ─╮\n│ #{command}\n│ cwd: #{runtime.workspace.root}\n╰#{'─' * 35}╯"
        $stdout.print "[y] Run once  [a] Always allow  [n] Deny: "
        answer = $stdin.gets.to_s.strip.downcase
        answer == "a" ? :always : answer == "y"
      end
    end
  end
end

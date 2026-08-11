# frozen_string_literal: true

require "io/console"

module Forge
  module UI
    # Terminal presentation primitives. Agent code emits data; these classes
    # decide how that data is presented and remain usable in narrow terminals.
    class Theme
      COLORS = { muted: :bright_black, info: :cyan, success: :green, warning: :yellow,
                 danger: :red, model: :magenta }.freeze

      def initialize(color: true)
        @pastel = Pastel.new(enabled: color)
      end

      def paint(kind, text)
        @pastel.public_send(COLORS.fetch(kind), text.to_s)
      end

      def bold(text) = @pastel.bold(text.to_s)
      def dim(text) = @pastel.dim(text.to_s)
    end

    class StatusBar
      def initialize(theme: Theme.new, width: nil)
        @theme = theme
        @width = width
      end

      def render(provider:, model:, mode:, workspace:, todos:, context: nil)
        width = @width || terminal_width
        path = shorten(workspace.to_s, [width / 3, 18].max)
        model = shorten(model.to_s, [width / 3, 16].max)
        context_text = context ? " #{context}" : ""
        line = "#{model} │ #{path} │ #{mode.to_s.upcase} │ #{todos} open#{context_text}"
        inner = " Cruks │ #{line} "
        if inner.length > width - 2
          inner = " Cruks │ #{model} │ #{mode.to_s.upcase} │ #{path} "
          inner = inner[0, width - 2]
        end
        top = "╭─#{inner.ljust([width - 3, 1].max, '─')}╮"
        top = top[0, width]
        @theme.paint(:muted, top) + "\n" +
          @theme.paint(:muted, "╰#{'─' * [width - 2, 1].max}╯")
      end

      private

      def terminal_width
        IO.console&.winsize&.last || ENV.fetch("COLUMNS", "80").to_i
      rescue StandardError
        80
      end

      def shorten(value, limit)
        return value if value.length <= limit

        "…#{value[-(limit - 1), limit - 1]}"
      end
    end

    class Activity
      FRAMES = %w[◐ ◓ ◑ ◒].freeze

      def initialize(theme: Theme.new, interactive: $stdout.tty?)
        @theme = theme
        @interactive = interactive
        @index = 0
      end

      def start(label)
        @label = label
        return unless @interactive

        $stdout.print(@theme.paint(:info, "#{frame} #{label}"))
        $stdout.flush
      end

      def update(label)
        finish
        start(label)
      end

      def finish
        return unless @label

        $stdout.print(@interactive ? "\r\e[2K" : "")
        @label = nil
      end

      private

      def frame
        value = FRAMES[@index % FRAMES.length]
        @index += 1
        value
      end
    end

    class ToolView
      def initialize(theme: Theme.new)
        @theme = theme
      end

      def render(name, arguments, result: nil, success: nil, duration: nil)
        title = name.to_s.sub(/\A(?:shell_execute|run_tests)\z/, "run")
        lines = ["  ┌─ #{@theme.bold(title.capitalize)}"]
        format_arguments(arguments).each { |line| lines << "  │ #{line}" }
        if result
          success_label = name.to_s.match?(/test|shell|command/) ? "✓ passed" : "✓ applied"
          state = success ? @theme.paint(:success, success_label) : @theme.paint(:danger, "✗ failed")
          state += " · #{duration}s" if duration
          lines << "  └─ #{state}"
        else
          lines << "  └─ #{@theme.paint(:info, 'running')}"
        end
        lines.join("\n")
      end

      private

      def format_arguments(arguments)
        hash = arguments.is_a?(Hash) ? arguments : {}
        hash.first(2).map do |key, value|
          text = value.to_s.gsub(/\s+/, " ")
          text = "#{text[0, 100]}…" if text.length > 100
          "#{key}: #{text}"
        end
      end
    end

    class Markdown
      def initialize(theme: Theme.new)
        @theme = theme
      end

      def render(text)
        in_code = false
        text.to_s.lines.map do |line|
          stripped = line.chomp
          if stripped.start_with?("```")
            in_code = !in_code
            next @theme.paint(:muted, "  │ #{stripped}")
          end
          next @theme.paint(:muted, "  │ #{stripped}") if in_code
          next @theme.bold(stripped) if stripped.match?(/\A#{Regexp.escape('#')}+\s+/)

          stripped
        end.compact.join("\n")
      end
    end

    class CompletionSummary
      def initialize(theme: Theme.new)
        @theme = theme
      end

      def render(summary, changed: [], verification: [])
        lines = ["╭─ #{@theme.paint(:success, 'Done')} #{'─' * 55}╮", "│ #{summary}"]
        unless changed.empty?
          lines << "│" << "│ Changed"
          changed.each { |line| lines << "│   #{line}" }
        end
        unless verification.empty?
          lines << "│" << "│ Verification"
          verification.each { |line| lines << "│   #{line}" }
        end
        lines << "╰#{'─' * 64}╯"
        lines.join("\n")
      end
    end
  end
end

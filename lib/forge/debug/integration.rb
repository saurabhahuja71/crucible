# frozen_string_literal: true

module Forge
  module Debug
    class Integration
      SUPPORTED = %w[debug byebug].freeze

      def initialize(workspace:)
        @workspace = workspace
      end

      def detect_debugger
        return "debug" if gem_available?("debug")
        return "byebug" if gem_available?("byebug")

        nil
      end

      def wrap_command(command, debugger: nil)
        dbg = debugger || detect_debugger
        case dbg
        when "debug"
          "ruby -rdebug -e '#{command.gsub("'", "\\\\'")}'"
        when "byebug"
          "bundle exec byebug -c '#{command}'"
        else
          command
        end
      end

      def analyze_error(output)
        lines = output.to_s.lines
        backtrace = lines.select { |l| l.match?(/:\d+:in/) }
        error_line = lines.find { |l| l.match?(/Error|Exception/) }

        {
          error: error_line&.strip,
          backtrace: backtrace.first(10).map(&:strip),
          suggestion: suggest_fix(error_line, backtrace)
        }
      end

      private

      def gem_available?(name)
        Gem::Specification.find_by_name(name)
        true
      rescue Gem::LoadError
        false
      end

      def suggest_fix(error_line, backtrace)
        return nil unless error_line

        case error_line
        when /NoMethodError/
          "Check method name and receiver type at #{backtrace.first}"
        when /NameError/
          "Verify constant/variable is defined and in scope"
        when /SyntaxError/
          "Review syntax near the reported line"
        else
          "Inspect backtrace and reproduce with minimal example"
        end
      end
    end

    class RemoteDebugger
      def initialize(ssh_manager:, host:)
        @ssh_manager = ssh_manager
        @host = host
      end

      def start_remote(port: 12345)
        conn = @ssh_manager.connection(@host)
        conn.forward_local(port, "127.0.0.1", port)
        "Remote debug port #{port} forwarded. Connect with: rdbg -A"
      end
    end
  end
end

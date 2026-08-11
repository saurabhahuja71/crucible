# frozen_string_literal: true

require "open3"
require "timeout"

module Forge
  module Tools
    class ShellExecute < Base
      def name = "shell_execute"
      def description = "Execute a shell command in the workspace directory. Subject to sandbox allow-list."
      def parameters
        {
          type: "object",
          properties: {
            command: { type: "string", description: "Shell command to execute" },
            timeout: { type: "integer", description: "Timeout in seconds (default 60)" }
          },
          required: ["command"]
        }
      end

      protected

      def execute(args)
        command = args["command"]
        timeout = (args["timeout"] || @sandbox.execution_timeout).to_i
        timeout = 1 if timeout < 1

        @sandbox.validate_command!(command)

        stdout, stderr, status = capture_with_limits(command, timeout)
        output = [stdout, stderr].reject(&:empty?).join("\n---\n")
        output = "(no output)" if output.empty?

        Result.new(
          output: "exit=#{status&.exitstatus || 124}\n#{output}",
          success: status&.success? || false
        )
      rescue Timeout::Error
        Result.new(output: "timed_out=true timeout=#{timeout}s", success: false, error: "Command timed out after #{timeout}s")
      end

      private

      def capture_with_limits(command, timeout)
        env = @sandbox.filtered_environment
        Open3.popen3(env, "/bin/sh", "-c", command, chdir: @workspace.root.to_s) do |stdin, stdout, stderr, wait_thr|
          stdin.close
          output = { out: +"", err: +"" }
          reader = Thread.new do
            [[:out, stdout], [:err, stderr]].each do |key, io|
              output[key] = io.read.to_s
            end
          end
          Timeout.timeout(timeout) { reader.join }
          limit = @sandbox.max_output_bytes
          output.each_key { |key| output[key] = "#{output[key][0, limit]}\n… truncated" if output[key].bytesize > limit }
          [output[:out], output[:err], wait_thr.value]
        end
      end
    end

    class RunTests < ShellExecute
      def name = "run_tests"
      def description = "Detect and run the project's configured test command with bounded output."
      def parameters
        { type: "object", properties: { command: { type: "string", description: "Optional explicit test command" }, timeout: { type: "integer" } } }
      end

      protected

      def execute(args)
        command = args["command"] || detect_command
        raise ToolError, "No test command detected; provide command explicitly" unless command
        super("command" => command, "timeout" => args["timeout"])
      end

      private

      def detect_command
        root = @workspace.root
        return "bundle exec rspec" if (root / "Gemfile").file? && (root / "spec").directory?
        return "bundle exec rake test" if (root / "Gemfile").file?
        return "npm test" if (root / "package.json").file?
        return "pytest" if (root / "pyproject.toml").file? || (root / "pytest.ini").file?
        return "go test ./..." if (root / "go.mod").file?
        return "cargo test" if (root / "Cargo.toml").file?
        return "mvn test" if (root / "pom.xml").file?
        nil
      end
    end
  end
end

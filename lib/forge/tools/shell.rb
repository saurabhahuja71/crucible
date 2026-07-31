# frozen_string_literal: true

require "open3"

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
        timeout = (args["timeout"] || 60).to_i

        @sandbox.validate_command!(command)

        stdout, stderr, status = Open3.capture3(command, chdir: @workspace.root.to_s)
        output = [stdout, stderr].reject(&:empty?).join("\n---\n")
        output = "(no output)" if output.empty?

        Result.new(
          output: "exit=#{status.exitstatus}\n#{output}",
          success: status.success?
        )
      end
    end
  end
end

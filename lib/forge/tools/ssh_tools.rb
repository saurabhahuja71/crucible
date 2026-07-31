# frozen_string_literal: true

module Forge
  module Tools
    class SSHExecute < Base
      def name = "ssh_execute"
      def description = "Execute a command on a remote SSH host."
      def parameters
        {
          type: "object",
          properties: {
            host: { type: "string", description: "SSH host name (from config)" },
            command: { type: "string", description: "Command to execute remotely" }
          },
          required: %w[host command]
        }
      end

      protected

      def execute(args)
        raise ToolError, "SSH manager not configured" unless @ssh_manager

        output = @ssh_manager.exec(args["host"], args["command"])
        Result.new(output: output)
      end
    end

    class SSHReadFile < Base
      def name = "ssh_read_file"
      def description = "Read a file from a remote SSH host."
      def parameters
        {
          type: "object",
          properties: {
            host: { type: "string", description: "SSH host name" },
            path: { type: "string", description: "Remote file path" }
          },
          required: %w[host path]
        }
      end

      protected

      def execute(args)
        raise ToolError, "SSH manager not configured" unless @ssh_manager

        output = @ssh_manager.connection(args["host"]).read_file(args["path"])
        Result.new(output: output)
      end
    end
  end
end

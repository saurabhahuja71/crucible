# frozen_string_literal: true

require "json"

module Forge
  module Tools
    class Result
      attr_reader :output, :error, :success

      def initialize(output: nil, error: nil, success: true)
        @output = output
        @error = error
        @success = success
      end

      def to_s
        error || output.to_s
      end

      def to_message_content
        if success
          output.is_a?(String) ? output : JSON.pretty_generate(output)
        else
          "Error: #{error}"
        end
      end
    end

    class Base
      attr_reader :name, :description, :parameters

      def initialize(workspace:, sandbox:, audit: nil, ssh_manager: nil)
        @workspace = workspace
        @sandbox = sandbox
        @audit = audit
        @ssh_manager = ssh_manager
      end

      def call(arguments)
        args = arguments.is_a?(String) ? JSON.parse(arguments) : arguments.transform_keys(&:to_s)
        audit(:tool_call, name: name, arguments: args)
        result = execute(args)
        audit(:tool_result, name: name, success: result.success, output: result.to_s[0, 500])
        result
      rescue SafetyError, ToolError => e
        Result.new(error: e.message, success: false)
      rescue JSON::ParserError => e
        Result.new(error: "Invalid arguments JSON: #{e.message}", success: false)
      rescue StandardError => e
        Forge.logger.error("#{name} failed: #{e.class}: #{e.message}")
        Result.new(error: "#{e.class}: #{e.message}", success: false)
      end

      def schema
        {
          type: "function",
          function: {
            name: name,
            description: description,
            parameters: parameters
          }
        }
      end

      protected

      def execute(_args)
        raise NotImplementedError
      end

      def resolve_path(path)
        @workspace.resolve(path)
      end

      def audit(event, details)
        @audit&.log(event, details)
      end
    end

    class Registry
      def initialize(tools)
        @tools = tools.each_with_object({}) { |t, h| h[t.name] = t }
      end

      def schemas
        @tools.values.map(&:schema)
      end

      def execute(name, arguments)
        tool = @tools[name]
        raise ToolError, "Unknown tool: #{name}" unless tool

        tool.call(arguments)
      end

      def names
        @tools.keys
      end

      def [](name)
        @tools[name]
      end

      def all
        @tools.values
      end
    end
  end
end

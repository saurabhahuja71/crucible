# frozen_string_literal: true

require "faraday"
require_relative "../agent/todos"

module Forge
  module Tools
    class AddTodo < Base
      def name = "add_todo"
      def description = "Add a task to the live todo list for a multi-step request."
      def parameters
        { type: "object", properties: { description: { type: "string" } }, required: ["description"] }
      end

      protected

      def execute(args)
        todo = Agent::TODO_STORE.add(args["description"])
        Result.new(output: "Added todo #{todo.id}: #{todo.description}")
      end
    end

    class CompleteTodo < Base
      def name = "complete_todo"
      def description = "Mark a todo item complete by id."
      def parameters
        { type: "object", properties: { id: { type: "integer" } }, required: ["id"] }
      end

      protected

      def execute(args)
        todo = Agent::TODO_STORE.complete(args["id"])
        Result.new(output: "Completed todo #{todo.id}: #{todo.description}")
      end
    end

    class UpdateTodo < Base
      def name = "update_todo"
      def description = "Update a todo description or completion state."
      def parameters
        { type: "object", properties: { id: { type: "integer" }, description: { type: "string" }, completed: { type: "boolean" } }, required: ["id"] }
      end

      protected

      def execute(args)
        todo = Agent::TODO_STORE.update(args["id"], description: args["description"], completed: args["completed"])
        Result.new(output: "Updated todo #{todo.id}: #{todo.description}")
      end
    end

    class ListTodos < Base
      def name = "list_todos"
      def description = "List the current live todo items."
      def parameters = { type: "object", properties: {} }

      protected

      def execute(_args)
        Result.new(output: Agent::TODO_STORE.format)
      end
    end

    class HttpRequest < Base
      def name = "http_request"
      def description = "Make a bounded HTTP request for API or health checks."
      def parameters
        { type: "object", properties: { method: { type: "string", enum: %w[get post] }, url: { type: "string" }, headers: { type: "object" }, body: { type: "string" } }, required: %w[method url] }
      end

      protected

      def execute(args)
        method = args["method"].to_s.downcase
        raise ToolError, "Only GET and POST are supported" unless %w[get post].include?(method)
        url = args["url"].to_s
        raise ToolError, "URL must use http or https" unless url.match?(/\Ahttps?:\/\//)

        response = Faraday.new(url: url) { |f| f.options.timeout = 30; f.options.open_timeout = 10 }.public_send(method) do |request|
          request.headers.update(args["headers"] || {})
          request.body = args["body"] if method == "post" && args["body"]
        end
        body = response.body.to_s
        body = "#{body[0, 12_000]}\n… truncated" if body.length > 12_000
        Result.new(output: "status=#{response.status}\n#{body}", success: response.success?, error: response.success? ? nil : "HTTP #{response.status}")
      rescue Faraday::Error => e
        Result.new(error: "HTTP request failed: #{e.message}", success: false)
      end
    end
  end
end

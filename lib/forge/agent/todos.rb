# frozen_string_literal: true

require "thread"

module Forge
  module Agent
    Todo = Struct.new(:id, :description, :completed, keyword_init: true)

    class TodoStore
      def initialize
        @items = []
        @next_id = 1
        @mutex = Mutex.new
      end

      def add(description)
        @mutex.synchronize do
          todo = Todo.new(id: @next_id, description: description.to_s.strip, completed: false)
          @next_id += 1
          @items << todo
          todo
        end
      end

      def complete(id)
        update(id, completed: true)
      end

      def update(id, description: nil, completed: nil)
        @mutex.synchronize do
          todo = find(id)
          todo.description = description if description
          todo.completed = completed unless completed.nil?
          todo
        end
      end

      def items
        @mutex.synchronize { @items.map(&:dup) }
      end

      def open_count
        @mutex.synchronize { @items.count { |item| !item.completed } }
      end

      def clear
        @mutex.synchronize { @items.clear }
      end

      def format
        current = items
        return "Tasks\n\n  (no tasks)\n\nProgress: 0/0 complete" if current.empty?

        rows = current.map { |item| "  #{item.completed ? '✓ [x]' : '○ [ ]'} #{item.id}. #{item.description}" }
        "Tasks\n\n#{rows.join("\n")}\n\nProgress: #{current.count(&:completed)}/#{current.length} complete"
      end

      private

      def find(id)
        todo = @items.find { |item| item.id == id.to_i }
        raise ToolError, "Unknown todo: #{id}" unless todo

        todo
      end
    end

    TODO_STORE = TodoStore.new
  end
end

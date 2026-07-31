# frozen_string_literal: true

module Forge
  module Parallel
    class Task
      attr_reader :id, :description, :status, :result, :error

      def initialize(id:, description:, &block)
        @id = id
        @description = description
        @block = block
        @status = :pending
        @result = nil
        @error = nil
        @mutex = Mutex.new
      end

      def run
        @mutex.synchronize { @status = :running }
        @result = @block.call
        @mutex.synchronize { @status = :completed }
        @result
      rescue StandardError => e
        @mutex.synchronize do
          @status = :failed
          @error = e.message
        end
        raise
      end
    end

    class Executor
      def initialize(config, on_progress: nil)
        @max_workers = config.fetch("parallel.max_workers", 4)
        @on_progress = on_progress
        @mutex = Mutex.new
      end

      def run_parallel(tasks)
        queue = Queue.new
        tasks.each { |t| queue << t }
        @max_workers.times { queue << :done }

        threads = @max_workers.times.map do
          Thread.new do
            loop do
              task = queue.pop
              break if task == :done

              notify(:start, task)
              task.run
              notify(:complete, task)
            rescue StandardError
              notify(:failed, task)
            end
          end
        end

        threads.each(&:join)
        tasks
      end

      def map(items, &block)
        tasks = items.map.with_index do |item, i|
          Task.new(id: i, description: item.to_s) { block.call(item) }
        end
        run_parallel(tasks)
        tasks.map(&:result)
      end

      private

      def notify(event, task)
        @on_progress&.call(event, task)
      end
    end

    class AgentWorker
      def initialize(parent_config:, workspace:, tools_builder:)
        @parent_config = parent_config
        @workspace = workspace
        @tools_builder = tools_builder
      end

      def spawn(task_description, on_event: nil)
        Thread.new do
          config = @parent_config
          workspace = Safety::Workspace.new(config, cwd: @workspace.root)
          sandbox = Safety::Sandbox.new(config)
          audit = Safety::AuditLogger.new(config)
          tools = @tools_builder.call(workspace: workspace, sandbox: sandbox, audit: audit)
          providers = Providers::Registry.build_failover_chain(config)
          chain = Providers::Failover.new(providers)

          loop = Agent::Loop.new(
            config: config,
            workspace: workspace,
            tools: tools,
            provider_chain: chain,
            on_event: on_event
          )
          loop.run(task_description, stream: false)
        end
      end
    end
  end
end

# frozen_string_literal: true

require "json"
require "securerandom"

module Forge
  module Agent
    class Session
      attr_reader :id, :messages, :metadata, :created_at

      def initialize(id: nil, messages: [], metadata: {})
        @id = id || SecureRandom.uuid
        @messages = messages
        @metadata = metadata
        @created_at = Time.now
      end

      def add_message(message)
        @messages << message
      end

      def save!
        path = session_path
        path.parent.mkpath
        File.write(path, JSON.pretty_generate(to_h))
        self
      end

      def self.load(id)
        path = session_dir.join("#{id}.json")
        raise Error, "Session not found: #{id}" unless path.exist?

        data = JSON.parse(path.read, symbolize_names: true)
        new(id: data[:id], messages: data[:messages], metadata: data[:metadata] || {})
      end

      def self.list
        dir = session_dir
        return [] unless dir.exist?

        dir.glob("*.json").map do |f|
          data = JSON.parse(f.read, symbolize_names: true)
          { id: data[:id], created_at: data[:created_at], message_count: data[:messages]&.size || 0 }
        end.sort_by { |s| s[:created_at] }.reverse
      end

      def self.session_dir
        DATA_DIR.join("sessions")
      end

      def to_h
        {
          id: @id,
          created_at: @created_at.utc.iso8601,
          metadata: @metadata,
          messages: @messages
        }
      end

      private

      def session_path
        self.class.session_dir.join("#{@id}.json")
      end
    end

    class Context
      def initialize(config, session)
        @config = config
        @session = session
        @summarize_after = config.fetch("agent.summarize_after_messages", 40)
      end

      def messages_for_provider
        msgs = []
        msgs << { role: "system", content: @config.fetch("agent.system_prompt") }
        msgs.concat(@session.messages)
        maybe_summarize!(msgs)
        msgs
      end

      def record_usage(usage)
        @session.metadata[:token_usage] ||= { "prompt" => 0, "completion" => 0 }
        @session.metadata[:token_usage]["prompt"] += usage["prompt_tokens"].to_i
        @session.metadata[:token_usage]["completion"] += usage["completion_tokens"].to_i
      end

      private

      def maybe_summarize!(msgs)
        return msgs if msgs.size < @summarize_after

        # Keep system + last N messages; mark for summarization in future enhancement
        system = msgs.first
        recent = msgs.last(@summarize_after / 2)
        [system, *recent]
      end
    end

    class Loop
      attr_reader :session, :tool_registry, :provider_chain
      attr_accessor :on_event

      def initialize(config:, workspace:, tools:, provider_chain:, session: nil, hooks: nil, on_event: nil)
        @config = config
        @workspace = workspace
        @tool_registry = tools
        @provider_chain = provider_chain
        @session = session || Session.new
        @context = Context.new(config, @session)
        @hooks = hooks || Hooks.new
        @on_event = on_event
        @max_turns = config.fetch("agent.max_turns", 50)
      end

      def run(user_input, stream: true)
        @session.add_message({ role: "user", content: user_input })
        emit(:user_message, content: user_input)

        turns = 0
        loop do
          turns += 1
          raise Error, "Max turns (#{@max_turns}) exceeded" if turns > @max_turns

          @hooks.run(:pre_turn, turn: turns, session: @session)

          response = chat_with_provider(stream: stream)
          @context.record_usage(response.usage) if response.usage

          if response.tool_calls?
            @session.add_message(response.to_message)
            execute_tool_calls(response.tool_calls)
          else
            content = response.content.to_s
            content = "(no response from model)" if content.empty?
            @session.add_message({ role: "assistant", content: content })
            emit(:assistant_message, content: content)
            @session.save!
            return content
          end
        end
      end

      private

      def chat_with_provider(stream:)
        messages = @context.messages_for_provider
        tools = @tool_registry.schemas

        @hooks.run(:pre_provider, messages: messages)

        if stream
          print_stream = @on_event ? proc { |type, data| emit(type, data) } : nil
          @provider_chain.chat(messages: messages, tools: tools, stream: true, &print_stream)
        else
          @provider_chain.chat(messages: messages, tools: tools, stream: false)
        end
      end

      def execute_tool_calls(tool_calls)
        tool_calls.each do |tc|
          result = nil
          emit(:tool_start, name: tc[:name], arguments: tc[:arguments])
          @hooks.run(:pre_tool, tool: tc[:name], arguments: tc[:arguments])

          result = @tool_registry.execute(tc[:name], tc[:arguments])
        rescue StandardError => e
          result = Tools::Result.new(error: e.message, success: false)

        ensure
          if result
            @hooks.run(:post_tool, tool: tc[:name], result: result)
            emit(:tool_end, name: tc[:name], output: result.to_s, success: result.success)

            @session.add_message({
                                   role: "tool",
                                   tool_call_id: tc[:id],
                                   name: tc[:name],
                                   content: result.to_message_content
                                 })
          end
        end
      end

      def emit(event, data = {})
        return unless @on_event

        @on_event.call(event, data)
      end
    end
  end
end

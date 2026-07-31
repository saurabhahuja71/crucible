# frozen_string_literal: true

require "json"

module Forge
  module Providers
    class Response
      attr_reader :content, :tool_calls, :finish_reason, :usage, :raw

      def initialize(content: nil, tool_calls: [], finish_reason: "stop", usage: {}, raw: {})
        @content = content
        @tool_calls = tool_calls
        @finish_reason = finish_reason
        @usage = usage
        @raw = raw
      end

      def tool_calls?
        tool_calls.any?
      end

      def to_message
        if tool_calls?
          {
            role: "assistant",
            content: content,
            tool_calls: tool_calls.map do |tc|
              {
                id: tc[:id],
                type: "function",
                function: { name: tc[:name], arguments: tc[:arguments].is_a?(String) ? tc[:arguments] : JSON.generate(tc[:arguments]) }
              }
            end
          }
        else
          { role: "assistant", content: content }
        end
      end
    end

    class Base
      attr_reader :name, :config

      def initialize(config, global_config:)
        @name = config["name"]
        @config = config
        @global_config = global_config
      end

      def chat(messages:, tools: nil, stream: false, &block)
        raise NotImplementedError
      end

      def model
        config["model"]
      end

      protected

      def api_key
        @global_config.resolve_env(config["api_key"])
      end

      def base_url
        config["base_url"].to_s.chomp("/")
      end

      def temperature
        config.fetch("temperature", 0.2)
      end

      def max_tokens
        config.fetch("max_tokens", 8192)
      end

      def timeout
        config.fetch("timeout", 120)
      end
    end
  end
end

# frozen_string_literal: true

require "faraday"
require "json"

module Forge
  module Providers
    class Ollama < Base
      def chat(messages:, tools: nil, stream: false, &block)
        body = {
          model: model,
          messages: normalize_messages(messages),
          stream: stream,
          options: {
            temperature: temperature,
            num_predict: max_tokens
          }
        }
        body[:tools] = tools if tools&.any?

        if stream
          stream_chat(body, &block)
        else
          response = connection.post("api/chat") do |req|
            req.headers["Content-Type"] = "application/json"
            req.body = JSON.generate(body)
          end
          parse_response(response)
        end
      end

      private

      def connection
        @connection ||= Faraday.new(url: base_url) do |f|
          f.options.timeout = timeout
          f.options.open_timeout = 10
          f.adapter Faraday.default_adapter
        end
      end

      def normalize_messages(messages)
        messages.map do |msg|
          m = { role: msg[:role] || msg["role"] }
          content = msg[:content] || msg["content"]
          m[:content] = content unless content.nil?
          m
        end
      end

      def parse_response(response)
        unless response.success?
          raise ProviderError, "Ollama error #{response.status}: #{response.body}"
        end

        data = JSON.parse(response.body)
        message = data["message"] || {}
        tool_calls = Array(message["tool_calls"]).map do |tc|
          fn = tc["function"] || {}
          {
            id: tc["id"] || SecureRandom.uuid,
            name: fn["name"],
            arguments: fn["arguments"].is_a?(Hash) ? fn["arguments"] : JSON.parse(fn["arguments"].to_s)
          }
        end

        Response.new(
          content: message["content"],
          tool_calls: tool_calls,
          finish_reason: data["done_reason"] || "stop",
          usage: {
            "prompt_tokens" => data["prompt_eval_count"],
            "completion_tokens" => data["eval_count"]
          },
          raw: data
        )
      end

      def stream_chat(body, &block)
        content_parts = []
        tool_calls = []

        connection.post("api/chat") do |req|
          req.headers["Content-Type"] = "application/json"
          req.body = JSON.generate(body)
          req.options.on_data = proc do |chunk, _size|
            chunk.to_s.split("\n").each do |line|
              next if line.strip.empty?

              data = JSON.parse(line)
              msg = data["message"] || {}
              if msg["content"]
                content_parts << msg["content"]
                block&.call(:content, msg["content"])
              end
              tool_calls = Array(msg["tool_calls"]).map do |tc|
                fn = tc["function"] || {}
                {
                  id: tc["id"] || SecureRandom.uuid,
                  name: fn["name"],
                  arguments: fn["arguments"].is_a?(Hash) ? fn["arguments"] : JSON.parse(fn["arguments"].to_s)
                }
              end
            end
          end
        end

        Response.new(
          content: content_parts.join,
          tool_calls: tool_calls,
          finish_reason: tool_calls.any? ? "tool_calls" : "stop"
        )
      end
    end
  end
end

require "securerandom"

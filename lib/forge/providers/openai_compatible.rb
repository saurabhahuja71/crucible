# frozen_string_literal: true

require "faraday"
require "faraday/retry"
require "json"

module Forge
  module Providers
    class OpenAICompatible < Base
      def chat(messages:, tools: nil, stream: false, &block)
        body = {
          model: model,
          messages: normalize_messages(messages),
          temperature: temperature,
          max_tokens: max_tokens,
          stream: stream
        }
        body[:tools] = tools if tools&.any?

        if stream
          stream_chat(body, &block)
        else
          response = connection.post("chat/completions") do |req|
            req.headers["Content-Type"] = "application/json"
            req.headers["Authorization"] = "Bearer #{api_key}" if api_key && !api_key.empty?
            req.body = JSON.generate(body)
          end
          parse_response(response)
        end
      end

      private

      def connection
        @connection ||= Faraday.new(url: base_url) do |f|
          f.request :retry, max: 2, interval: 0.5, backoff_factor: 2
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
          m[:tool_calls] = msg[:tool_calls] if msg[:tool_calls]
          m[:tool_call_id] = msg[:tool_call_id] if msg[:tool_call_id]
          m[:name] = msg[:name] if msg[:name]
          m
        end
      end

      def parse_response(response)
        unless response.success?
          raise ProviderError, "API error #{response.status}: #{response.body}"
        end

        data = JSON.parse(response.body)
        choice = data["choices"]&.first
        raise ProviderError, "No choices in response" unless choice

        message = choice["message"]
        tool_calls = Array(message["tool_calls"]).map do |tc|
          {
            id: tc["id"],
            name: tc.dig("function", "name"),
            arguments: JSON.parse(tc.dig("function", "arguments") || "{}")
          }
        end

        Response.new(
          content: message["content"],
          tool_calls: tool_calls,
          finish_reason: choice["finish_reason"],
          usage: data["usage"] || {},
          raw: data
        )
      end

      def stream_chat(body, &block)
        content_parts = []
        tool_calls_acc = {}
        usage = {}

        connection.post("chat/completions") do |req|
          req.headers["Content-Type"] = "application/json"
          req.headers["Authorization"] = "Bearer #{api_key}" if api_key && !api_key.empty?
          req.body = JSON.generate(body)
          req.options.on_data = proc do |chunk, _size|
            chunk.to_s.split("\n").each do |line|
              next unless line.start_with?("data: ")
              payload = line.delete_prefix("data: ").strip
              next if payload.empty? || payload == "[DONE]"

              data = JSON.parse(payload)
              usage = data["usage"] if data["usage"]
              delta = data.dig("choices", 0, "delta") || {}
              if delta["content"]
                content_parts << delta["content"]
                block&.call(:content, delta["content"])
              end
              accumulate_tool_calls(tool_calls_acc, delta["tool_calls"])
            end
          end
        end

        tool_calls = finalize_tool_calls(tool_calls_acc)
        Response.new(
          content: content_parts.join,
          tool_calls: tool_calls,
          finish_reason: tool_calls.any? ? "tool_calls" : "stop",
          usage: usage
        )
      end

      def accumulate_tool_calls(acc, deltas)
        Array(deltas).each do |tc|
          idx = tc["index"] || 0
          acc[idx] ||= { id: nil, name: nil, arguments: +"" }
          acc[idx][:id] ||= tc["id"]
          if tc.dig("function", "name")
            acc[idx][:name] = tc.dig("function", "name")
          end
          acc[idx][:arguments] << tc.dig("function", "arguments").to_s
        end
      end

      def finalize_tool_calls(acc)
        acc.sort_by(&:first).filter_map do |_idx, tc|
          next if tc[:name].nil? || tc[:name].empty?

          {
            id: tc[:id] || SecureRandom.uuid,
            name: tc[:name],
            arguments: JSON.parse(tc[:arguments].empty? ? "{}" : tc[:arguments])
          }
        end
      end
    end
  end
end

require "securerandom"

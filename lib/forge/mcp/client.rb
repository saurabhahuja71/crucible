# frozen_string_literal: true

require "json"

module Forge
  module MCP
  class Client
    def initialize(server_config)
      @config = server_config
      @tools = []
    end

    def connect
      # MCP over stdio transport
      @cmd = @config["command"]
      @args = Array(@config["args"])
      Forge.logger.info("MCP: connecting to #{@config['name']}")
      discover_tools
      self
    end

    def tool_schemas
      @tools.map do |tool|
        {
          type: "function",
          function: {
            name: "mcp_#{@config['name']}_#{tool['name']}",
            description: tool["description"],
            parameters: tool["inputSchema"] || { type: "object", properties: {} }
          }
        }
      end
    end

    def call_tool(name, arguments)
      # Placeholder for full MCP JSON-RPC protocol
      Forge.logger.info("MCP tool call: #{name} #{arguments}")
      { content: "MCP tool #{name} executed (stub)" }
    end

    private

    def discover_tools
      @tools = Array(@config["tools"])
    end
  end

  class Manager
    def initialize(config)
      @config = config
      @clients = []
    end

    def load_servers
      servers = Array(@config.fetch("mcp.servers"))
      @clients = servers.map do |srv|
        Client.new(srv).connect
      end
      self
    end

    def all_tool_schemas
      @clients.flat_map(&:tool_schemas)
    end
  end
  end
end

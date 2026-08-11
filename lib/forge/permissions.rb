# frozen_string_literal: true

require "json"
require "thread"

module Forge
  module Permissions
    Request = Struct.new(:tool_name, :arguments, keyword_init: true)
    ASK = "ask"
    ALLOW = "allow"
    PLAN = "plan"

    class Manager
      CAPABILITY_TOOLS = %w[write_file edit_file apply_patch shell_execute ssh_execute http_request].freeze

      attr_accessor :handler
      attr_reader :mode

      def initialize(config, handler: nil)
        @config = config
        @mode = config.fetch("permission_mode", ASK).to_s
        @mode = ASK unless [ASK, ALLOW, PLAN].include?(@mode)
        @handler = handler
        @mutex = Mutex.new
        @persistent = load_persistent
      end

      def set_mode(value)
        value = value.to_s.downcase
        raise ConfigurationError, "Permission mode must be ask, allow, or plan" unless [ASK, ALLOW, PLAN].include?(value)

        @mode = value
      end

      def authorize!(tool_name, arguments)
        return true unless CAPABILITY_TOOLS.include?(tool_name.to_s)
        return true if @mode == ALLOW
        raise SafetyError, "Plan mode blocks capability tool #{tool_name}" if @mode == PLAN

        key = permission_key(tool_name, arguments)
        return true if @persistent[key]
        request = Request.new(tool_name: tool_name.to_s, arguments: arguments)
        decision = @handler ? @handler.call(request) : false
        case decision
        when :always, "always"
          @persistent[key] = true
          save_persistent
          true
        when true, :once, "once"
          true
        else
          raise SafetyError, "Permission denied for #{tool_name}"
        end
      end

      def approvals
        @mutex.synchronize { @persistent.keys.sort }
      end

      def remove(key)
        removed = @mutex.synchronize { !@persistent.delete(key).nil? }
        save_persistent if removed
        removed
      end

      private

      def permission_key(tool_name, arguments)
        "#{tool_name}:#{JSON.generate(arguments.sort.to_h)}"
      end

      def permission_path
        @config.expand_path(@config.fetch("permissions.path", "~/.local/share/cruks/permissions.json"))
      end

      def load_persistent
        path = permission_path
        return {} unless path.file?

        JSON.parse(path.read)
      rescue JSON::ParserError
        {}
      end

      def save_persistent
        path = permission_path
        path.parent.mkpath
        path.write(JSON.pretty_generate(@persistent))
      end
    end
  end
end

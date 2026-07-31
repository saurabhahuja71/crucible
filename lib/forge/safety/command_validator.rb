# frozen_string_literal: true

module Forge
  module Safety
    class CommandValidator
      BLOCKED_PATTERNS = [
        /\brm\s+-rf\s+\//,
        /\bsudo\b/,
        /\bmkfs\b/,
        /\bdd\s+if=/,
        />\s*\/dev\/sd/,
        /\bchmod\s+777\b/,
        /\bcurl\b.*\|\s*sh\b/,
        /\bwget\b.*\|\s*sh\b/
      ].freeze

      def initialize(allowed_commands:, sandbox: true)
        @sandbox = sandbox
        @allowed = Array(allowed_commands)
      end

      def validate!(command)
        return unless @sandbox

        cmd = command.strip
        BLOCKED_PATTERNS.each do |pattern|
          raise SafetyError, "Blocked dangerous command pattern" if cmd.match?(pattern)
        end

        base_cmd = extract_base_command(cmd)
        return if base_cmd.nil?

        unless @allowed.include?(base_cmd)
          raise SafetyError, "Command not in allow-list: #{base_cmd}. Allowed: #{@allowed.join(', ')}"
        end
      end

      private

      def extract_base_command(cmd)
        cmd.split(/\s+/).first&.sub(/\A.*\//, "")
      end
    end
  end
end

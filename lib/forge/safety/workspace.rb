# frozen_string_literal: true

require "pathname"

module Forge
  module Safety
    class Workspace
      attr_reader :root, :trusted, :auto_approve

      def initialize(config, cwd: Dir.pwd)
        @root = Pathname(cwd).expand_path
        @trusted = config.fetch("workspace.trust", false)
        @auto_approve = config.fetch("workspace.auto_approve", false)
      end

      def resolve(path, write: false)
        resolved = normalize_path(path)

        return resolved if within_workspace?(resolved)
        return resolved if !write && @trusted && within_home?(resolved)

        raise SafetyError, "Path escapes workspace: #{path} -> #{resolved}"
      end

      def normalize_path(path)
        str = path.to_s
        if str.start_with?("~/") || str == "~"
          Pathname(File.expand_path(str))
        elsif str.start_with?("/")
          Pathname(str).expand_path
        else
          (@root + str).expand_path
        end
      end

      def within_home?(path)
        home = Pathname(Dir.home).expand_path.to_s
        Pathname(path).expand_path.to_s.start_with?(home)
      end

      def within_workspace?(path)
        path = Pathname(path).expand_path
        path.to_s.start_with?(@root.to_s)
      end

      def destructive?(action, path: nil)
        case action
        when :write, :delete, :shell
          !@auto_approve
        else
          false
        end
      end
    end

    class Sandbox
      def initialize(config)
        @validator = CommandValidator.new(
          allowed_commands: config.fetch("safety.allowed_commands", Configuration.default_allowed_commands),
          sandbox: config.fetch("safety.sandbox_shell", true)
        )
        @blocked_paths = Array(config.fetch("safety.blocked_paths", [])).map do |p|
          Pathname(p).expand_path.to_s
        end
      end

      def validate_command!(command)
        @validator.validate!(command)
      end

      def validate_path_access!(path)
        expanded = Pathname(path).expand_path.to_s
        @blocked_paths.each do |blocked|
          if expanded.start_with?(blocked)
            raise SafetyError, "Access to blocked path: #{path}"
          end
        end
      end
    end

    class AuditLogger
      def initialize(config)
        path = config.expand_path(config.fetch("logging.audit_path").to_s)
        path.parent.mkpath
        @file = File.open(path, "a")
        @mutex = Mutex.new
      end

      def log(event, details = {})
        entry = {
          timestamp: Time.now.utc.iso8601(3),
          event: event,
          **details
        }
        @mutex.synchronize do
          @file.puts(JSON.generate(entry))
          @file.flush
        end
      end

      def close
        @file.close
      end
    end
  end
end

require "json"

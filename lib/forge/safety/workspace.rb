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

        return validate_real_path!(resolved, write: write) if within_workspace?(resolved)
        return validate_real_path!(resolved, write: write) if !write && @trusted && within_home?(resolved)

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
        value = Pathname(path).expand_path.to_s
        value == home || value.start_with?("#{home}#{File::SEPARATOR}")
      end

      def within_workspace?(path)
        path = Pathname(path).expand_path
        path.to_s == @root.to_s || path.to_s.start_with?("#{@root}#{File::SEPARATOR}")
      end

      private

      def validate_real_path!(path, write:)
        candidate = path.expand_path
        existing = candidate
        existing = existing.parent until existing.exist? || existing.root?
        real = Pathname(existing.realpath)
        boundary = if within_workspace?(candidate)
                     Pathname(@root.realpath)
                   else
                     Pathname(Dir.home).realpath
                   end
        inside = real.to_s == boundary.to_s || real.to_s.start_with?("#{boundary}#{File::SEPARATOR}")
        raise SafetyError, "Symlink escapes allowed boundary: #{path}" unless inside

        candidate
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
      attr_reader :execution_timeout, :max_output_bytes

      def initialize(config)
        @execution_timeout = config.fetch("execution.timeout", 60).to_i
        @max_output_bytes = config.fetch("execution.max_output_bytes", 32_000).to_i
        @environment_allowlist = Array(config.fetch("execution.environment_allowlist", []))
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

      def filtered_environment
        return ENV.to_h if @environment_allowlist.include?("*")

        ENV.to_h.select do |key, _value|
          @environment_allowlist.include?(key) || key.match?(/\A(PATH|HOME|USER|LANG|LC_[A-Z_]+|TERM)\z/)
        end
      end
    end

    class AuditLogger
      def initialize(config)
        @disabled = config.fetch("logging.enabled", true) == false
        return if @disabled
        path = config.expand_path(config.fetch("logging.audit_path").to_s)
        path.parent.mkpath
        @file = File.open(path, "a")
        @mutex = Mutex.new
      end

      def log(event, details = {})
        return if @disabled
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
        @file&.close
      end
    end
  end
end

require "json"

# frozen_string_literal: true

require "net/ssh"
require "toml-rb"
require "open3"

module Forge
  module SSH
    class Host
      attr_reader :name, :host, :user, :port, :key_path, :password, :proxy_jump

      def initialize(name:, host:, user: nil, port: 22, key_path: nil, password: nil, proxy_jump: nil)
        @name = name
        @host = host
        @user = user || ENV["USER"]
        @port = port
        @key_path = key_path
        @password = password
        @proxy_jump = proxy_jump
      end

      def to_h
        { name: name, host: host, user: user, port: port, key_path: key_path }
      end
    end

    class Connection
      attr_reader :host

      def initialize(host_config)
        @host = host_config
        @session = nil
        @mutex = Mutex.new
      end

      def connect!
        @mutex.synchronize do
          return @session if @session&.active?

          options = { port: @host.port, timeout: 30 }
          options[:keys] = [@host.key_path] if @host.key_path
          options[:password] = @host.password if @host.password

          @session = Net::SSH.start(@host.host, @host.user, **options)
        end
      end

      def exec(command)
        connect!
        output = +""
        @session.exec!(command) do |_ch, stream, data|
          output << data
        end
        output
      end

      def read_file(remote_path)
        connect!
        output = +""
        @session.exec!("cat #{Shellwords.escape(remote_path)}") do |_ch, _stream, data|
          output << data
        end
        output
      end

      def write_file(remote_path, content)
        connect!
        encoded = content.gsub("'", "'\\\\''")
        @session.exec!("mkdir -p $(dirname #{Shellwords.escape(remote_path)}) && printf '%s' '#{encoded}' > #{Shellwords.escape(remote_path)}")
      end

      def forward_local(local_port, remote_host, remote_port)
        connect!
        @session.forward.local(local_port, remote_host, remote_port)
      end

      def close
        @session&.close
        @session = nil
      end
    end

    class SystemConnection
      def initialize(host_config)
        @host = host_config
      end

      def connect!
        self
      end

      def exec(command)
        argv = ["ssh", "-J", @host.proxy_jump, "-o", "BatchMode=yes", "#{@host.user}@#{@host.host}", command]
        stdout, stderr, status = Open3.capture3(*argv)
        output = [stdout, stderr].reject(&:empty?).join
        raise Error, "SSH command failed (#{status.exitstatus}): #{output}" unless status.success?

        output
      end

      def read_file(remote_path)
        path = remote_path.to_s.sub(/\A~(?=\/|$)/, "/home/#{@host.user}")
        exec("cat #{Shellwords.escape(path)}")
      end

      def close; end
    end

    class Manager
      def initialize(config)
        @config = config
        @connections = {}
        @hosts = load_hosts
        @mutex = Mutex.new
        @command_validator = Safety::CommandValidator.new(
          allowed_commands: config.fetch("ssh.allowed_commands", Configuration.default_allowed_commands),
          sandbox: true
        )
      end

      def add_host(host)
        @mutex.synchronize do
          @hosts[host.name] = host
          save_hosts!
        end
      end

      def connect(name)
        host = @hosts[name] || @hosts.values.find { |candidate| candidate.host == name }
        raise Error, "Unknown SSH host: #{name}" unless host

        @mutex.synchronize do
          @connections[name] ||= if host.proxy_jump
                                   SystemConnection.new(host)
                                 else
                                   Connection.new(host)
                                 end
        end
        @connections[name].connect!
      end

      def connection(name)
        connect(name)
        @connections[name]
      end

      def remote_exec(name, command)
        validated_command = command.sub(/\Asudo\s+(?:-n\s+)?/, "")
        @command_validator.validate!(validated_command)
        connection(name).exec(command)
      end

      def exec(name, command)
        remote_exec(name, command)
      end

      def list_hosts
        @hosts.values
      end

      def disconnect(name)
        @mutex.synchronize do
          @connections[name]&.close
          @connections.delete(name)
        end
      end

      def disconnect_all
        @connections.each_value(&:close)
        @connections.clear
      end

      private

      def config_path
        @config.expand_path(@config.fetch("ssh.config_path"))
      end

      def load_hosts
        path = config_path
        data = path.exist? ? TomlRB.load_file(path.to_s) : {}
        hosts = Array(data["hosts"]).each_with_object({}) do |h, acc|
          host = Host.new(
            name: h["name"],
            host: h["host"],
            user: h["user"],
            port: h["port"] || 22,
            key_path: h["key_path"],
            password: h["password"]
          )
          acc[host.name] = host
        end
        hosts.merge!(load_bash_alias_hosts)
        hosts
      rescue TomlRB::ParseError
        {}
      end

      def load_bash_alias_hosts
        path = Pathname(Dir.home).join(".bashrc")
        return {} unless path.file?

        path.readlines.filter_map do |line|
          match = line.match(/^\s*alias\s+([\w-]+)=['"]ssh\s+-J\s+([^\s'"]+)\s+([^'"]+)['"]\s*$/)
          next unless match

          name, jump, destination = match.captures
          user, host = destination.split("@", 2)
          next unless host

          [name, Host.new(name: name, host: host, user: user, proxy_jump: jump)]
        end.to_h
      rescue SystemCallError
        {}
      end

      def save_hosts!
        path = config_path
        path.parent.mkpath
        data = { hosts: @hosts.values.map(&:to_h) }
        File.write(path, TomlRB.dump(data))
      end
    end
  end
end

require "shellwords"

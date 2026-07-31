# frozen_string_literal: true

require "net/ssh"
require "toml-rb"

module Forge
  module SSH
    class Host
      attr_reader :name, :host, :user, :port, :key_path, :password

      def initialize(name:, host:, user: nil, port: 22, key_path: nil, password: nil)
        @name = name
        @host = host
        @user = user || ENV["USER"]
        @port = port
        @key_path = key_path
        @password = password
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
        host = @hosts[name]
        raise Error, "Unknown SSH host: #{name}" unless host

        @mutex.synchronize do
          @connections[name] ||= Connection.new(host)
        end
        @connections[name].connect!
      end

      def connection(name)
        connect(name)
        @connections[name]
      end

      def remote_exec(name, command)
        @command_validator.validate!(command)
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
        return {} unless path.exist?

        data = TomlRB.load_file(path.to_s)
        Array(data["hosts"]).each_with_object({}) do |h, acc|
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
      rescue TomlRB::ParseError
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

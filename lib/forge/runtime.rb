# frozen_string_literal: true

module Forge
  class Runtime
    attr_reader :config, :workspace, :sandbox, :audit, :tools, :provider_chain,
                :ssh_manager, :agent_loop, :skills, :permissions

    def initialize(config_path: nil, cwd: Dir.pwd, model: nil, trust: false)
      @config = Configuration.load(config_path)
      apply_model_override!(model) if model
      @workspace = Safety::Workspace.new(@config, cwd: cwd)
      @workspace.instance_variable_set(:@trusted, true) if trust
      @sandbox = Safety::Sandbox.new(@config)
      @audit = Safety::AuditLogger.new(@config)
      @ssh_manager = SSH::Manager.new(@config)
      @permissions = Permissions::Manager.new(@config)
      @skills = Skills::Loader.load_all(tool_deps)
      rebuild_stack!
    end

    def rebuild_stack!
      ssh_deps = tool_deps.merge(ssh_manager: @ssh_manager)
      all_tools = Tools::Builtin.all(**tool_deps) + [
        Tools::SSHExecute.new(**ssh_deps),
        Tools::SSHReadFile.new(**ssh_deps)
      ] + @skills
      @tools = Tools::Registry.new(all_tools, permissions: @permissions)
      providers = Providers::Registry.build_failover_chain(@config)
      @provider_chain = Providers::Failover.new(providers)
      @agent_loop = Agent::Loop.new(
        config: @config,
        workspace: @workspace,
        tools: @tools,
        provider_chain: @provider_chain
      )
    end

    def switch_provider(name)
      @config.data["providers"]["primary"] = name
      rebuild_stack!
    end

    def set_permission_mode(mode)
      @permissions.set_mode(mode)
      @config.data["permission_mode"] = @permissions.mode
    end

    def resume_session(id)
      session = Agent::Session.load(id)
      @agent_loop = Agent::Loop.new(
        config: @config,
        workspace: @workspace,
        tools: @tools,
        provider_chain: @provider_chain,
        session: session
      )
    end

    def new_session
      @agent_loop = Agent::Loop.new(
        config: @config,
        workspace: @workspace,
        tools: @tools,
        provider_chain: @provider_chain
      )
    end

    def available_models
      primary = @config.fetch("providers.primary")
      configured = Array(@config.fetch("providers.#{primary}.models", []))
      ([ @config.fetch("providers.#{primary}.model") ] + configured).compact.uniq
    end

    def switch_model(name)
      primary = @config.fetch("providers.primary")
      @config.data["providers"][primary]["model"] = name
      rebuild_stack!
    end

    def run_parallel_agents(descriptions, &on_progress)
      worker = Parallel::AgentWorker.new(
        parent_config: @config,
        workspace: @workspace,
        tools_builder: method(:build_tools_registry)
      )

      threads = descriptions.map do |desc|
        worker.spawn(desc)
      end

      threads.map(&:value)
    end

    def exec(task, stream: false)
      @agent_loop.run(task, stream: stream)
    end

    def apply_model_override!(model)
      primary = @config.fetch("providers.primary")
      @config.data["providers"][primary] ||= {}
      @config.data["providers"][primary]["model"] = model
    end

    private

    def tool_deps
      { workspace: @workspace, sandbox: @sandbox, audit: @audit, ssh_manager: @ssh_manager }
    end

    def build_tools_registry(workspace:, sandbox:, audit:)
      all = Tools::Builtin.all(workspace: workspace, sandbox: sandbox, audit: audit, ssh_manager: @ssh_manager)
      Tools::Registry.new(all, permissions: @permissions)
    end
  end
end

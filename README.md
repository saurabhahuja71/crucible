# Forge

**Forge** is a production-quality, local-first terminal coding agent written in Ruby. It provides an interactive TUI for AI-assisted software engineering with full tool calling, provider failover, SSH remote execution, parallel sub-agents, and a safety-first workspace model.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLI / TUI Layer                         │
│  forge (interactive)  │  forge exec  │  slash commands          │
└──────────────────────────────┬──────────────────────────────────┘
                               │
┌──────────────────────────────▼──────────────────────────────────┐
│                      Agent Loop (Core)                          │
│  Session ─ Context ─ Hooks ─ Turn management ─ Summarization    │
└──────────────────────────────┬──────────────────────────────────┘
                               │
         ┌─────────────────────┼─────────────────────┐
         ▼                     ▼                     ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│ Provider Chain  │  │  Tool Registry  │  │  Safety Layer   │
│ OpenAI-compat   │  │  Filesystem     │  │  Workspace trust│
│ Ollama          │  │  Shell / Git    │  │  Sandbox        │
│ Failover        │  │  SSH / Skills   │  │  Audit log      │
└─────────────────┘  └─────────────────┘  └─────────────────┘
         │                     │                     │
         └─────────────────────┼─────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│              Parallel Executor  │  SSH Manager  │  MCP Client    │
└─────────────────────────────────────────────────────────────────┘
```

### Technology Choices

| Component | Choice | Rationale |
|-----------|--------|-----------|
| HTTP client | `faraday` + `faraday-retry` | Mature, middleware-friendly |
| Config | `toml-rb` | Human-readable, comments |
| TUI | `tty-prompt`, `tty-box`, `pastel` | Modern Ruby terminal UX |
| SSH | `net-ssh` | Standard Ruby SSH library |
| Autoloading | `zeitwerk` | Clean module structure |
| Concurrency | Ruby threads | Simple parallel tool/agent execution |
| Search | `rg` via system call | Fast, respects .gitignore |

## Installation

```bash
# From source
git clone https://github.com/user/dboper/cruks.git
cd cruks
bundle install
bundle exec rake install   # installs `forge` and `cruks-s` to PATH

# Or build the gem
gem build forge.gemspec
gem install forge-0.1.0.gem
```

## Build & Run with SGLang (`cruks-s`)

Same workflow as `forge-s` for the Rust agent — uses your existing `~/.sglang-tunnel.bash` helpers (`sglang-up`, `sglang-tunnel`, `_sglang_ensure_api`).

### 1. Build

```bash
cd /path/to/cruks
bundle install
```

Optional global install:

```bash
bundle exec rake install
# or add to PATH for dev:
export PATH="/path/to/cruks/exe:$PATH"
```

### 2. Ensure SGLang is reachable

```bash
sglang-up          # tunnel + start remote server if needed
# or, if server already running:
sglang-tunnel
```

### 3. Launch Cruks via SGLang

```bash
# From repo (no install needed)
./exe/cruks-s                    # interactive TUI
./exe/cruks-s exec "list *.rb"   # headless one-shot

# Or via script
./scripts/cruks-sglang.sh
```

### 4. Optional bash alias (like `forge-s`)

Add to `~/.bashrc`:

```bash
alias cruks-s='/scratch/sauahuja/gobin/goprojects/src/github.com/user/dboper/cruks/exe/cruks-s'
# or after gem install:
alias cruks-s='cruks-s'
```

`cruks-s` will:
1. Call `_sglang_ensure_api` (tunnel to `:30000` on heavyinstance)
2. Auto-detect the live model from `/v1/models`
3. Launch with `config/cruks.sglang.toml`, `--trust`, and `--model <id>`

Config: `config/cruks.sglang.toml` — points at `http://127.0.0.1:30000/v1`, provider `sglang`, API key `sglang`.

Override paths:

```bash
export CRUKS_ROOT=/path/to/cruks
export CRUKS_SGLANG_CFG=/path/to/my.toml
cruks-s
```

## Quick Start

```bash
# Create default config
forge init

# Edit ~/.config/forge/config.toml — set your API key
export OPENAI_API_KEY=sk-...

# Interactive session
forge

# Headless single task
forge exec "list all Ruby files and summarize the project structure"

# List saved sessions
forge sessions
```

## Configuration

Copy `config/forge.example.toml` to `~/.config/forge/config.toml` or place `forge.toml` in your project root.

```toml
[providers]
primary = "openai"
failover = ["ollama"]

[providers.openai]
type = "openai_compatible"
api_key = "${OPENAI_API_KEY}"
base_url = "https://api.openai.com/v1"
model = "gpt-4o"

[providers.ollama]
type = "ollama"
base_url = "http://localhost:11434"
model = "llama3.2"
```

### Supported Providers

Any OpenAI-compatible API works out of the box:

- **OpenAI** — default `base_url`
- **Azure OpenAI** — set `base_url` to your deployment endpoint
- **Groq, Together, Fireworks, DeepSeek** — set `base_url` and `api_key`
- **Ollama** — native support via `type = "ollama"`

Provider failover is automatic: if the primary fails, Forge tries each provider in the `failover` list.

## Slash Commands

| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/model [name]` | Show or switch provider |
| `/tools` | List available tools |
| `/ssh list\|connect <name>` | Manage SSH connections |
| `/parallel task1; task2` | Run parallel sub-agents |
| `/debug on\|off` | Toggle debug mode |
| `/clear` | Clear screen |
| `/resume [id]` | List or resume sessions |
| `/skills` | List loaded skills |
| `/trust` | Trust current workspace |
| `/auto on\|off` | Toggle auto-approve (⚠ risky) |
| `/exit` | Exit Forge |

## Built-in Tools

| Tool | Description |
|------|-------------|
| `read_file` | Read file with line numbers |
| `write_file` | Write/create files |
| `edit_file` | Surgical string replacement |
| `list_directory` | List directory contents |
| `search_files` | Ripgrep content search |
| `shell_execute` | Run sandboxed shell commands |
| `git_status` | Git status |
| `git_diff` | Git diff |
| `git_log` | Recent commits |
| `ssh_execute` | Run command on remote host |
| `ssh_read_file` | Read remote file |

## Safety Model

Forge enforces a workspace trust model:

1. **Path validation** — tools cannot access paths outside the workspace
2. **Command allow-list** — local shell and SSH `remote_exec` validate against `safety.allowed_commands` and `ssh.allowed_commands` (~90 common dev commands by default: `docker`, `podman`, `systemctl`, `journalctl`, `ssh`, `sed`, `awk`, `curl`, `tar`, etc.)
3. **Blocked patterns** — `sudo`, `rm -rf /`, pipe-to-shell, etc.
4. **Audit logging** — all tool calls logged to `~/.local/share/forge/audit.log`
5. **Confirmation prompts** — destructive actions require approval (unless `/trust` + `/auto`)

## SSH Configuration

Add hosts to `~/.config/forge/ssh_hosts.toml`:

```toml
[[hosts]]
name = "prod"
host = "10.0.0.1"
user = "deploy"
port = 22
key_path = "~/.ssh/id_rsa"
```

## Skills / Plugins

Place Ruby skill files in `~/.local/share/forge/skills/` or `.forge/skills/`:

```ruby
# my_skill.rb
class Skill < Forge::Tools::Base
  def name = "deploy"
  def description = "Deploy the application"
  def parameters
    { type: "object", properties: { env: { type: "string" } }, required: ["env"] }
  end

  protected

  def execute(args)
  Forge::Tools::Result.new(output: "Deployed to #{args['env']}")
  end
end
```

## Project Structure

```
forge/
├── exe/forge                 # CLI executable
├── config/forge.example.toml # Example configuration
├── lib/forge/
│   ├── agent/                # Agent loop, session, context
│   ├── providers/            # LLM provider adapters
│   ├── tools/                # Built-in tool implementations
│   ├── tui/                  # Terminal UI
│   ├── ssh/                  # SSH connection manager
│   ├── parallel/             # Parallel execution
│   ├── safety/               # Workspace, sandbox, audit
│   ├── skills/               # Plugin loader
│   ├── mcp/                  # MCP client (stub)
│   ├── debug/                # Debugger integration
│   ├── configuration.rb      # TOML config loader
│   ├── runtime.rb            # Application wiring
│   ├── hooks.rb              # Lifecycle hooks
│   └── cli.rb                # CLI entry point
└── spec/                     # RSpec tests
```

## Development

```bash
bundle install
bundle exec rspec
bundle exec forge --help
```

## License

MIT

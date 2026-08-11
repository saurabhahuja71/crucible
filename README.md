# Cruks

**Cruks** is a production-quality, local-first terminal coding agent written in Ruby. It provides an interactive TUI for AI-assisted software engineering with full tool calling, provider failover, SSH remote execution, parallel sub-agents, and a safety-first workspace model.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLI / TUI Layer                         │
│  cruks (interactive)  │  cruks exec  │  slash commands          │
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
bundle exec rake install   # installs `cruks` and `cruks-s` to PATH

# Or build the gem
gem build cruks.gemspec
gem install cruks-0.1.0.gem
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

### 4. Bash alias (like `pi-s` / `forge-s`)

Add to `~/.bashrc`:

```bash
source /scratch/sauahuja/gobin/goprojects/src/github.com/user/dboper/cruks/scripts/cruks-sglang.sh
alias cruks-s='cruks-sglang'
```

Or one-liner without sourcing:

```bash
alias cruks-s='/scratch/sauahuja/gobin/goprojects/src/github.com/user/dboper/cruks/exe/cruks-s'
```

`cruks-s` will:
1. Call `_sglang_ensure_api` (tunnel to `:30000` on heavyinstance)
2. Auto-detect the live model from `/v1/models`
3. Launch with `config/cruks.sglang.toml`, `--trust`, and `--model <id>`

Backend shortcuts:

- `cruks-s1` sources the dedicated Ollama helper, warms the S1 model, and uses the `:11435` tunnel.
- `cruks-s2` uses the dedicated SGLang-2 helper, Darwin tool-call settings, and the `:30002` local tunnel.

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
cruks init

# Edit ~/.config/cruks/config.toml — set your API key
export OPENAI_API_KEY=sk-...

# Interactive session
cruks

# Headless single task
cruks exec "list all Ruby files and summarize the project structure"

# List saved sessions
cruks sessions
```

## Configuration

Copy `config/cruks.example.toml` to `~/.config/cruks/config.toml` or place `cruks.toml` in your project root.

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

### Caching and privacy

Cruks deliberately does not cache provider responses, Google results, API keys,
or arbitrary command output. Sessions are persisted locally under
`~/.local/share/cruks/sessions/` so they can be resumed, and the agent bounds
large file and command output before it reaches the model. Context reduction
keeps the system prompt and recent conversation; it does not upload a hidden
cache to a third party.

If a deployment adds Google Search or another external retrieval service, keep
that cache outside Cruks and make its policy explicit: use a short TTL for
volatile results, key entries by the complete normalized request and locale,
exclude credentials and personalized responses, and honor the service's cache
and deletion requirements. The current `http_request` tool is bounded HTTP
access, not a Google cache implementation.

### Supported Providers

Any OpenAI-compatible API works out of the box:

- **OpenAI** — default `base_url`
- **Azure OpenAI** — set `base_url` to your deployment endpoint
- **Groq, Together, Fireworks, DeepSeek** — set `base_url` and `api_key`
- **Ollama** — native support via `type = "ollama"`

Provider failover is automatic: if the primary fails, Forge tries each provider in the `failover` list.

## Slash Commands

The interactive launcher prints the command shortcuts at startup. The most useful
ones are `/help`, `/mode ask|allow|plan`, `/todo`, `/model`, `/permissions`, and
`/new`; these work identically through the S1 Ollama and S2 SGLang launchers.

| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/model [name]` | Show or switch the active model |
| `/mode ask\|allow\|plan` | Change permission mode |
| `/permissions [ask\|allow\|plan\|toggle]` | Toggle or inspect permissions |
| `/mouse on\|off` | Toggle terminal mouse reporting |
| `/theme dark\|light` | Change display theme preference |
| `/todo [add DESC\|done ID\|clear]` | Manage the live todo list |
| `/scroll up\|down\|top\|bottom` | Browse long transcript output with a scrollbar |
| `/queue` | Show queued work (interactive input is serial) |
| `/tools` | List available tools |
| `/ssh list\|connect <name>` | Manage SSH connections |
| `/parallel task1; task2` | Run parallel sub-agents |
| `/debug on\|off` | Toggle debug mode |
| `/clear` | Clear screen |
| `/resume [id]` | List or resume sessions |
| `/skills` | List loaded skills |
| `/trust` | Trust current workspace |
| `/auto on\|off` | Toggle auto-approve (⚠ risky) |
| `/permissions [remove <key>]` | List or remove permanent tool approvals |
| `/status` | Show current model, mode, workspace, tasks, and changes |
| `/doctor` | Diagnose the local provider and workspace |
| `/changes` | Summarize working-tree changes |
| `/diff` | Show the current unstaged diff |
| `/logs` | Show recent audit diagnostics |
| `/history` | Show recent conversation messages |
| `/sessions` | List saved sessions |
| `/new` | Start a fresh session |
| `/exit` | Exit Forge |

The interactive footer always shows the active permission mode and its controls:
`/mode ask|allow|plan` and `/permissions toggle`. Use `--no-color` for plain
terminal output, `--debug` for verbose diagnostics, or `--json` with `exec` or
`--prompt` for automation.

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
| `add_todo`, `complete_todo`, `update_todo`, `list_todos` | Track multi-step work |
| `http_request` | Bounded GET/POST API checks |

## Safety Model

Cruks enforces a workspace trust and permission model:

1. **Path validation** — tools cannot access paths outside the workspace
2. **Command allow-list** — local shell and SSH `remote_exec` validate against `safety.allowed_commands` and `ssh.allowed_commands` (~90 common dev commands by default: `docker`, `podman`, `systemctl`, `journalctl`, `ssh`, `sed`, `awk`, `curl`, `tar`, etc.)
3. **Blocked patterns** — `sudo`, `rm -rf /`, pipe-to-shell, etc.
4. **Permission modes** — `ask` confirms capability tools, `allow` permits them, and `plan` blocks them
5. **Persistent approvals** — exact approvals are stored in `~/.local/share/cruks/permissions.json`
6. **Audit logging** — all tool calls logged to `~/.local/share/cruks/audit.log`
7. **Confirmation prompts** — destructive actions require approval (unless `/auto on`)

## SSH Configuration

Add hosts to `~/.config/cruks/ssh_hosts.toml`:

```toml
[[hosts]]
name = "prod"
host = "10.0.0.1"
user = "deploy"
port = 22
key_path = "~/.ssh/id_rsa"
```

## Skills / Plugins

Place Ruby skill files in `~/.local/share/cruks/skills/` or `.cruks/skills/`:

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
cruks/
├── exe/cruks                 # CLI executable
├── exe/cruks-s               # SGLang shortcut
├── config/cruks.example.toml # Example configuration
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
bundle exec cruks --help
```

## License

MIT

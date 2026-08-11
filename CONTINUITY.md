# Cruks continuity

## Latest audit (2026-08-11)

- `prompt.xt` now contains an implementation audit and records the completed gaps.
- Added file metadata/search/symbol/patch tools, Git show/branch tools, automatic `run_tests`, bounded shell execution, environment filtering, and configurable audit logging.
- Hardened workspace symlink and sibling-prefix boundary checks; added `ask` alias and `--provider` CLI support.
- Added regression coverage; `ruby -S rspec` passes 32 examples and all Ruby files pass syntax checks.
- Docker isolation and full-screen rendering remain documented deployment limitations.
- Pre-existing working-tree items `.gitignore`, `lib/forge/cli.rb`, and `hi` were preserved; review staged scope before push.
- TUI follow-up added visible status/footer shortcuts, `/mouse on|off`, permission toggles, richer todo commands, and transcript scrolling via `/scroll up|down|top|bottom`.
- Professional UI upgrade is in progress in `lib/forge/ui/terminal.rb` and `lib/forge/tui/app.rb`: status/activity/tool/Markdown/completion components, `/status`, `/doctor`, `/changes`, `/diff`, `/logs`, `/history`, `/sessions`, `--prompt`, `--json`, `--debug`, `--verbose`, and `--no-color` are implemented and focused UI tests are present.

- Ruby local-first coding agent in `lib/forge/`, exposed as the `cruks` gem and CLI.
- Existing architecture includes OpenAI-compatible/Ollama providers with failover, sessions, skills, SSH, parallel agents, MCP scaffolding, filesystem/shell/git tools, safety validation, audit logging, and a terminal UI.
- Latest feature parity work added `ask`/`allow`/`plan` permission modes with persistent exact approvals, live todo tools/store, bounded HTTP requests, model switching, theme state, session reset, and matching slash commands.
- Validation: `ruby -S rspec --format progress` passes 28 examples; all Ruby files pass `ruby -c`; direct feature smoke checks pass.
- Existing unrelated working-tree items (`hi`, `scripts/cruks-ollama.sh`, and `.gitignore` changes) were preserved and not included.
- Next useful work: replace the line-oriented Reline UI with a richer full-screen TUI if desired, and add provider discovery/model picker plus streamed tool approval widgets.
- Launcher fix: S1 sources `scripts/cruks-ollama.sh` after `_ollama1_ensure`; S2 calls the dedicated `cruks-s2` function so `_sglang2_ensure` selects local `:30002` and the Darwin tool parser.
- S2 verification: direct local SGLang chat and end-to-end `cruks-s2 exec "Reply with exactly OK"` both return `OK` when the dedicated function is active; reload existing shells to remove the old alias.
- Remote fix: SSH aliases such as `podman9` are discovered from `.bashrc`, routed through the configured jump host, and remote `sudo` is validated against the underlying allow-listed command. The agent prompt forbids SSH-through-shell fallback and repeated identical retries.
- Remote read-only verification: `ssh -J bastion opc@10.0.2.183 "sudo podman ps -a --format 'table {{.ID}}\\t{{.Image}}\\t{{.Status}}\\t{{.Names}}'"` returned `rac-dnsserver`, `racnodep1`, and `racnodep2`, all Up; no containers were started or stopped by this check.
- Noise/failure fix: remote `~` paths now expand to the remote user's home, searches for the word `sudo` are no longer falsely blocked, `echo` is allow-listed, and launcher provider logs default to warning level.
- Interactive noise fix: successful tool cards are suppressed, only concise tool failures are shown, launcher max turns are 16, and Podman requests are instructed to perform one status check before deciding whether a start is needed.

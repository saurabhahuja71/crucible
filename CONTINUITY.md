# Cruks continuity

- Ruby local-first coding agent in `lib/forge/`, exposed as the `cruks` gem and CLI.
- Existing architecture includes OpenAI-compatible/Ollama providers with failover, sessions, skills, SSH, parallel agents, MCP scaffolding, filesystem/shell/git tools, safety validation, audit logging, and a terminal UI.
- Latest feature parity work added `ask`/`allow`/`plan` permission modes with persistent exact approvals, live todo tools/store, bounded HTTP requests, model switching, theme state, session reset, and matching slash commands.
- Validation: `ruby -S rspec --format progress` passes 28 examples; all Ruby files pass `ruby -c`; direct feature smoke checks pass.
- Existing unrelated working-tree items (`hi`, `scripts/cruks-ollama.sh`, and `.gitignore` changes) were preserved and not included.
- Next useful work: replace the line-oriented Reline UI with a richer full-screen TUI if desired, and add provider discovery/model picker plus streamed tool approval widgets.

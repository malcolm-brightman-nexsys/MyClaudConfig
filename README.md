# MyClaudConfig

Idempotent setup script that restores a complete Claude Code environment on any machine.

## What It Configures

- **Dependencies:** Node.js (via nvm) if missing
- **Settings:** Status line, enabled plugins
- **Plugins:** superpowers, code-simplifier, context7
- **MCP Servers:** Google Calendar, Gmail, sequential-thinking

## Usage

```bash
git clone <repo-url> && cd MyClaudConfig
chmod +x setup.sh
./setup.sh
```

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) must be installed
- Internet connection (for nvm, plugins, MCP registration)

## Re-running

The script is idempotent — safe to re-run at any time. It skips already-configured items and updates changed settings.

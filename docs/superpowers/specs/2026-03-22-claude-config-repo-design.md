# Claude Config Repo Design

## Purpose

A Git repository that can be cloned onto any new machine to fully restore a Claude Code environment — settings, plugins, MCP servers, and dependencies — via a single idempotent shell script.

## Requirements

- Script-based setup (`setup.sh`) using `claude` CLI commands
- Full bootstrap: installs Node.js if missing, configures all Claude components
- Registers remote MCP servers without triggering auth (user authenticates on first use)
- Idempotent: safe to re-run, skips already-configured items, updates changed items

## Repo Layout

```
MyClaudConfig/
├── setup.sh              # Main setup script (executable)
├── settings.json         # Source-of-truth for ~/.claude/settings.json
├── .gitignore            # Prevent committing sensitive files
└── README.md             # Usage: clone, chmod +x, run
```

## Script Design: `setup.sh`

### Function: `check_deps`

- Checks for `node` and `npx` via `command -v`
- If missing, installs Node.js LTS via nvm (downloads nvm if needed, uses `nvm install --lts`)
- Checks for `claude` CLI; exits with a clear error message if not found (Claude Code installation varies by platform and is left to the user)

### Function: `configure_settings`

- Reads `settings.json` from the repo (source of truth)
- Reads existing `~/.claude/settings.json` if present
- Merges using `node -e` with a JSON deep merge: repo values win, extra keys in the existing file are preserved
- Creates `~/.claude/` directory if it doesn't exist
- Writes the merged result to `~/.claude/settings.json`

### Function: `install_plugins`

Installs 3 plugins from `claude-plugins-official` marketplace at user scope. For each plugin, checks `claude plugin list` output to determine if already installed before running `claude plugin install`.

Plugins:
- `superpowers@claude-plugins-official`
- `code-simplifier@claude-plugins-official`
- `context7@claude-plugins-official`

### Function: `configure_mcps`

Registers MCP servers via `claude mcp add` with `--scope user`. Checks `claude mcp list` output before adding to skip already-registered servers.

MCP servers (full commands):
- `claude mcp add --transport http -s user "claude.ai Google Calendar" https://gcal.mcp.claude.com/mcp`
- `claude mcp add --transport http -s user "claude.ai Gmail" https://gmail.mcp.claude.com/mcp`
- `claude mcp add -s user sequential-thinking -- npx -y @modelcontextprotocol/server-sequential-thinking`

Note: The context7 MCP server is automatically registered by the context7 plugin and does not need a manual `claude mcp add`.

### Function: `print_summary`

Prints a summary of what was applied vs skipped during the run.

## Idempotency Strategy

| Component | Check | Action if missing |
|-----------|-------|-------------------|
| Node.js | `command -v node` | Install via nvm |
| Claude CLI | `command -v claude` | Exit with instructions |
| Settings | Deep merge (repo wins, preserves extras) | Write merged JSON |
| Plugins | Parse `claude plugin list` output | `claude plugin install` |
| MCP servers | Parse `claude mcp list` output | `claude mcp add -s user` |

## Settings Source of Truth

`settings.json` in the repo root:

```json
{
  "statusLine": {
    "type": "command",
    "command": "npx -y ccstatusline@latest",
    "padding": 0
  },
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "code-simplifier@claude-plugins-official": true,
    "context7@claude-plugins-official": true
  }
}
```

## Error Handling

The script uses a continue-and-report strategy:
- Each function tracks its own success/failure state
- If a step fails (e.g., plugin install, MCP add), it logs the error and continues with remaining items
- The `print_summary` function reports all failures at the end
- Exit code is non-zero if any step failed
- Exception: if `claude` CLI is not found, the script exits immediately (nothing else can proceed)

## Repo Layout: `.gitignore`

A `.gitignore` is included to prevent accidental commits of sensitive files:
- `.env`
- `*.credentials*`
- `node_modules/`

## What Is Not Included

- Claude CLI installation (platform-specific, left to user)
- MCP server authentication (happens on first use)
- Project-level settings (`settings.local.json`) — these are project-specific
- Session data, history, or credentials
- Only the settings keys listed in `settings.json` are managed; the deep-merge preserves any additional user-local settings

# MyClaudConfig

Idempotent setup script that restores a complete Claude Code environment on any machine. Supports both Linux/macOS (bash) and Windows (PowerShell).

## What It Configures

- **Dependencies:** Node.js (via nvm on Linux/macOS, winget/Chocolatey on Windows) if missing
- **Settings:** Status line, enabled plugins
- **Plugins:** superpowers, code-simplifier, context7
- **MCP Servers:** Google Calendar, Gmail, sequential-thinking

## Usage

### Linux / macOS

```bash
git clone <repo-url> && cd MyClaudConfig
chmod +x setup.sh
./setup.sh
```

### Windows (PowerShell)

```powershell
git clone <repo-url>; cd MyClaudConfig
.\setup.ps1
```

If blocked by execution policy, run with:

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1
```

Or set the policy for your user once:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

**Note:** On Windows, MCP servers that rely on `npx` are launched through a `cmd /c` wrapper (e.g., `cmd /c npx -y @modelcontextprotocol/server-sequential-thinking`). This is required because Claude Code's stdio transport on Windows needs `cmd /c` to correctly spawn Node-based MCP processes.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) must be installed
- Internet connection (for nvm/winget, plugins, MCP registration)
- **Linux/macOS:** bash
- **Windows:** PowerShell 5.1 or later

## Re-running

The script is idempotent — safe to re-run at any time. It skips already-configured items and updates changed settings.

## Inspiration

- [How to make Claude Code less dumb](https://www.youtube.com/watch?v=-O6MEtleOdA) by Michia Rohrssen

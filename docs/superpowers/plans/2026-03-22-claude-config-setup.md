# Claude Config Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create an idempotent shell script and supporting files that fully restore a Claude Code environment on any new machine.

**Architecture:** Single `setup.sh` script with discrete functions for each concern (deps, settings, plugins, MCPs). Uses `node -e` for JSON merging and `claude` CLI for all Claude configuration. Continue-and-report error handling with summary at the end.

**Tech Stack:** Bash, Node.js (for JSON merge), Claude CLI

**Spec:** `docs/superpowers/specs/2026-03-22-claude-config-repo-design.md`

---

## File Structure

| File | Responsibility |
|------|---------------|
| `setup.sh` | Main setup script — all logic lives here |
| `settings.json` | Source-of-truth for `~/.claude/settings.json` |
| `.gitignore` | Prevent committing sensitive files |
| `README.md` | Usage instructions |

---

### Task 1: Create `.gitignore`

**Files:**
- Create: `.gitignore`

- [ ] **Step 1: Write `.gitignore`**

```
.env
*.credentials*
node_modules/
```

- [ ] **Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: add .gitignore"
```

---

### Task 2: Create `settings.json`

**Files:**
- Create: `settings.json`

- [ ] **Step 1: Write `settings.json`**

This is the source-of-truth for `~/.claude/settings.json`:

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

- [ ] **Step 2: Validate it's valid JSON**

Run: `node -e "JSON.parse(require('fs').readFileSync('settings.json','utf8')); console.log('Valid JSON')"`
Expected: `Valid JSON`

- [ ] **Step 3: Commit**

```bash
git add settings.json
git commit -m "chore: add settings.json source-of-truth"
```

---

### Task 3: Create `setup.sh` — scaffold and `check_deps`

**Files:**
- Create: `setup.sh`

- [ ] **Step 1: Write the script scaffold with `check_deps`**

```bash
#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Track failures for summary
FAILURES=()
APPLIED=()
SKIPPED=()

log_info()  { printf "\033[1;34m[INFO]\033[0m  %s\n" "$1"; }
log_ok()    { printf "\033[1;32m[OK]\033[0m    %s\n" "$1"; }
log_warn()  { printf "\033[1;33m[WARN]\033[0m  %s\n" "$1"; }
log_fail()  { printf "\033[1;31m[FAIL]\033[0m  %s\n" "$1"; }

check_deps() {
    log_info "Checking dependencies..."

    # Check for node/npx
    if ! command -v node &>/dev/null; then
        log_warn "Node.js not found. Installing via nvm..."
        if ! command -v nvm &>/dev/null; then
            log_info "Installing nvm..."
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
            export NVM_DIR="$HOME/.nvm"
            # shellcheck disable=SC1091
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        fi
        nvm install --lts
        nvm use --lts
        if command -v node &>/dev/null; then
            APPLIED+=("Node.js (installed via nvm)")
            log_ok "Node.js installed: $(node --version)"
        else
            log_fail "Failed to install Node.js"
            FAILURES+=("Node.js installation")
            return 1
        fi
    else
        SKIPPED+=("Node.js (already installed: $(node --version))")
        log_ok "Node.js found: $(node --version)"
    fi

    # Check for claude CLI
    if ! command -v claude &>/dev/null; then
        log_fail "Claude CLI not found. Please install Claude Code first:"
        log_fail "  https://docs.anthropic.com/en/docs/claude-code"
        exit 1
    fi
    log_ok "Claude CLI found"
}
```

- [ ] **Step 2: Make it executable and test `check_deps`**

Run: `chmod +x setup.sh && bash setup.sh`
Expected: Should show Node.js found, Claude CLI found (or install Node.js if missing)

- [ ] **Step 3: Commit**

```bash
git add setup.sh
git commit -m "feat: add setup.sh scaffold with check_deps"
```

---

### Task 4: Add `configure_settings` function

**Files:**
- Modify: `setup.sh`

- [ ] **Step 1: Add `configure_settings` function after `check_deps`**

```bash
configure_settings() {
    log_info "Configuring settings..."

    local repo_settings="$SCRIPT_DIR/settings.json"
    local claude_dir="$HOME/.claude"
    local target_settings="$claude_dir/settings.json"

    if [ ! -f "$repo_settings" ]; then
        log_fail "settings.json not found in repo"
        FAILURES+=("Settings: settings.json not found in repo")
        return 1
    fi

    mkdir -p "$claude_dir"

    if [ ! -f "$target_settings" ]; then
        cp "$repo_settings" "$target_settings"
        APPLIED+=("Settings (created ~/.claude/settings.json)")
        log_ok "Created ~/.claude/settings.json"
        return 0
    fi

    # Deep merge: repo values win, existing extra keys preserved
    local merged
    merged=$(node -e "
        const fs = require('fs');
        const repo = JSON.parse(fs.readFileSync('$repo_settings', 'utf8'));
        const existing = JSON.parse(fs.readFileSync('$target_settings', 'utf8'));
        function deepMerge(target, source) {
            for (const key of Object.keys(source)) {
                if (source[key] && typeof source[key] === 'object' && !Array.isArray(source[key])
                    && target[key] && typeof target[key] === 'object' && !Array.isArray(target[key])) {
                    deepMerge(target[key], source[key]);
                } else {
                    target[key] = source[key];
                }
            }
            return target;
        }
        const result = deepMerge(existing, repo);
        console.log(JSON.stringify(result, null, 2));
    " 2>&1)

    if [ $? -ne 0 ]; then
        log_fail "Failed to merge settings: $merged"
        FAILURES+=("Settings: JSON merge failed")
        return 1
    fi

    echo "$merged" > "$target_settings"
    APPLIED+=("Settings (merged into ~/.claude/settings.json)")
    log_ok "Merged settings into ~/.claude/settings.json"
}
```

- [ ] **Step 2: Test `configure_settings`**

Run: `bash setup.sh`
Expected: Should show settings merged or created

- [ ] **Step 3: Commit**

```bash
git add setup.sh
git commit -m "feat: add configure_settings with JSON deep merge"
```

---

### Task 5: Add `install_plugins` function

**Files:**
- Modify: `setup.sh`

- [ ] **Step 1: Add `install_plugins` function**

```bash
install_plugins() {
    log_info "Installing plugins..."

    local plugins=(
        "superpowers@claude-plugins-official"
        "code-simplifier@claude-plugins-official"
        "context7@claude-plugins-official"
    )

    local installed
    installed=$(claude plugin list 2>/dev/null || echo "")

    for plugin in "${plugins[@]}"; do
        if echo "$installed" | grep -qF "$plugin"; then
            SKIPPED+=("Plugin: $plugin (already installed)")
            log_ok "Plugin already installed: $plugin"
        else
            log_info "Installing plugin: $plugin"
            if claude plugin install "$plugin" 2>&1; then
                APPLIED+=("Plugin: $plugin")
                log_ok "Installed plugin: $plugin"
            else
                log_fail "Failed to install plugin: $plugin"
                FAILURES+=("Plugin: $plugin")
            fi
        fi
    done
}
```

- [ ] **Step 2: Test `install_plugins`**

Run: `bash setup.sh`
Expected: Should show plugins skipped (already installed) or installed

- [ ] **Step 3: Commit**

```bash
git add setup.sh
git commit -m "feat: add install_plugins function"
```

---

### Task 6: Add `configure_mcps` function

**Files:**
- Modify: `setup.sh`

- [ ] **Step 1: Add `configure_mcps` function**

```bash
configure_mcps() {
    log_info "Configuring MCP servers..."

    local existing_mcps
    existing_mcps=$(claude mcp list 2>/dev/null || echo "")

    # Google Calendar (remote HTTP)
    if echo "$existing_mcps" | grep -q "Google Calendar"; then
        SKIPPED+=("MCP: claude.ai Google Calendar (already registered)")
        log_ok "MCP already registered: claude.ai Google Calendar"
    else
        log_info "Adding MCP: claude.ai Google Calendar"
        if claude mcp add --transport http -s user "claude.ai Google Calendar" https://gcal.mcp.claude.com/mcp 2>&1; then
            APPLIED+=("MCP: claude.ai Google Calendar")
            log_ok "Added MCP: claude.ai Google Calendar"
        else
            log_fail "Failed to add MCP: claude.ai Google Calendar"
            FAILURES+=("MCP: claude.ai Google Calendar")
        fi
    fi

    # Gmail (remote HTTP)
    if echo "$existing_mcps" | grep -q "Gmail"; then
        SKIPPED+=("MCP: claude.ai Gmail (already registered)")
        log_ok "MCP already registered: claude.ai Gmail"
    else
        log_info "Adding MCP: claude.ai Gmail"
        if claude mcp add --transport http -s user "claude.ai Gmail" https://gmail.mcp.claude.com/mcp 2>&1; then
            APPLIED+=("MCP: claude.ai Gmail")
            log_ok "Added MCP: claude.ai Gmail"
        else
            log_fail "Failed to add MCP: claude.ai Gmail"
            FAILURES+=("MCP: claude.ai Gmail")
        fi
    fi

    # Sequential Thinking (npx stdio)
    if echo "$existing_mcps" | grep -q "sequential-thinking"; then
        SKIPPED+=("MCP: sequential-thinking (already registered)")
        log_ok "MCP already registered: sequential-thinking"
    else
        log_info "Adding MCP: sequential-thinking"
        if claude mcp add -s user sequential-thinking -- npx -y @modelcontextprotocol/server-sequential-thinking 2>&1; then
            APPLIED+=("MCP: sequential-thinking")
            log_ok "Added MCP: sequential-thinking"
        else
            log_fail "Failed to add MCP: sequential-thinking"
            FAILURES+=("MCP: sequential-thinking")
        fi
    fi
}
```

- [ ] **Step 2: Test `configure_mcps`**

Run: `bash setup.sh`
Expected: Should show MCPs skipped (already registered) or added

- [ ] **Step 3: Commit**

```bash
git add setup.sh
git commit -m "feat: add configure_mcps function"
```

---

### Task 7: Add `print_summary` and main execution

**Files:**
- Modify: `setup.sh`

- [ ] **Step 1: Add `print_summary` and main block**

```bash
print_summary() {
    echo ""
    echo "========================================"
    echo "  Claude Config Setup Summary"
    echo "========================================"

    local applied_count=${#APPLIED[@]}
    local skipped_count=${#SKIPPED[@]}
    local failure_count=${#FAILURES[@]}

    if [ "$applied_count" -gt 0 ]; then
        echo ""
        log_ok "Applied ($applied_count):"
        for item in "${APPLIED[@]}"; do
            echo "    - $item"
        done
    fi

    if [ "$skipped_count" -gt 0 ]; then
        echo ""
        log_info "Skipped ($skipped_count):"
        for item in "${SKIPPED[@]}"; do
            echo "    - $item"
        done
    fi

    if [ "$failure_count" -gt 0 ]; then
        echo ""
        log_fail "Failed ($failure_count):"
        for item in "${FAILURES[@]}"; do
            echo "    - $item"
        done
    fi

    echo ""
    echo "========================================"

    if [ "$failure_count" -gt 0 ]; then
        return 1
    fi
    return 0
}

# Main execution
main() {
    echo ""
    echo "========================================"
    echo "  Claude Code Setup"
    echo "========================================"
    echo ""

    check_deps || { print_summary; exit 1; }
    configure_settings
    install_plugins
    configure_mcps
    print_summary
    exit $?
}

main
```

- [ ] **Step 2: Full end-to-end test**

Run: `bash setup.sh`
Expected: Full run with summary showing all items as skipped (since this machine is already configured)

- [ ] **Step 3: Commit**

```bash
git add setup.sh
git commit -m "feat: add print_summary and main execution block"
```

---

### Task 8: Create `README.md`

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write `README.md`**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with usage instructions"
```

---

### Task 9: Final validation

- [ ] **Step 1: Run the full script**

Run: `bash setup.sh`
Expected: Clean run, all items either applied or skipped, zero failures, exit code 0

- [ ] **Step 2: Run the script a second time**

Run: `bash setup.sh`
Expected: All items show as skipped (idempotency verified), exit code 0

- [ ] **Step 3: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: address issues found during validation"
```

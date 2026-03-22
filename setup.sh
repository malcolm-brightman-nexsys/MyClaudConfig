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

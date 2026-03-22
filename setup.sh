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

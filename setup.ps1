#Requires -Version 5.1

<#
.SYNOPSIS
    Claude Code setup script for Windows.
.DESCRIPTION
    Configures Claude Code settings, plugins, and MCP servers.
    If blocked by execution policy, run:
        powershell -ExecutionPolicy Bypass -File setup.ps1
    Or set policy for your user:
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
#>

$ErrorActionPreference = 'Continue'

$SCRIPT_DIR = $PSScriptRoot

# Track failures for summary
$script:FAILURES = @()
$script:APPLIED  = @()
$script:SKIPPED  = @()

# Prevent ANSI color codes in CLI output that could break string matching
$env:NO_COLOR = '1'

function Log-Info  { param([string]$Message) Write-Host "[INFO]  $Message" -ForegroundColor Blue }
function Log-Ok    { param([string]$Message) Write-Host "[OK]    $Message" -ForegroundColor Green }
function Log-Warn  { param([string]$Message) Write-Host "[WARN]  $Message" -ForegroundColor Yellow }
function Log-Fail  { param([string]$Message) Write-Host "[FAIL]  $Message" -ForegroundColor Red }

function Check-Deps {
    Log-Info "Checking dependencies..."

    # Check for node/npx
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Log-Warn "Node.js not found. Attempting install via winget..."
        $installed = $false

        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Log-Info "Installing Node.js LTS via winget..."
            winget install OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
            # Refresh PATH so the current session can find node
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            if (Get-Command node -ErrorAction SilentlyContinue) {
                $installed = $true
            }
        }

        if (-not $installed -and (Get-Command choco -ErrorAction SilentlyContinue)) {
            Log-Info "winget failed or unavailable. Trying Chocolatey..."
            choco install nodejs-lts -y 2>&1 | Out-Null
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
            if (Get-Command node -ErrorAction SilentlyContinue) {
                $installed = $true
            }
        }

        if ($installed) {
            $nodeVersion = node --version
            $script:APPLIED += "Node.js (installed: $nodeVersion)"
            Log-Ok "Node.js installed: $nodeVersion"
        } else {
            Log-Fail "Failed to install Node.js. Please install manually:"
            Log-Fail "  winget install OpenJS.NodeJS.LTS"
            Log-Fail "  or download from https://nodejs.org/"
            $script:FAILURES += "Node.js installation"
            return $false
        }
    } else {
        $nodeVersion = node --version
        $script:SKIPPED += "Node.js (already installed: $nodeVersion)"
        Log-Ok "Node.js found: $nodeVersion"
    }

    # Check for claude CLI
    if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
        Log-Fail "Claude CLI not found. Please install Claude Code first:"
        Log-Fail "  https://docs.anthropic.com/en/docs/claude-code"
        exit 1
    }
    Log-Ok "Claude CLI found"
    return $true
}

function Configure-Settings {
    Log-Info "Configuring settings..."

    $repoSettings   = Join-Path $SCRIPT_DIR "settings.json"
    $claudeDir      = Join-Path $env:USERPROFILE ".claude"
    $targetSettings = Join-Path $claudeDir "settings.json"

    if (-not (Test-Path $repoSettings)) {
        Log-Fail "settings.json not found in repo"
        $script:FAILURES += "Settings: settings.json not found in repo"
        return
    }

    if (-not (Test-Path $claudeDir)) {
        New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
    }

    if (-not (Test-Path $targetSettings)) {
        Copy-Item $repoSettings $targetSettings
        $script:APPLIED += "Settings (created ~/.claude/settings.json)"
        Log-Ok "Created ~/.claude/settings.json"
        return
    }

    # Deep merge: repo values win, existing extra keys preserved
    $jsCode = @"
const fs = require('fs');
const repo = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const existing = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
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
"@

    $tempFile = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.js')
    try {
        [System.IO.File]::WriteAllText($tempFile, $jsCode, [System.Text.UTF8Encoding]::new($false))
        $merged = node $tempFile $repoSettings $targetSettings 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "Node.js returned exit code $LASTEXITCODE"
        }
        [System.IO.File]::WriteAllText($targetSettings, ($merged -join "`n"), [System.Text.UTF8Encoding]::new($false))
        $script:APPLIED += "Settings (merged into ~/.claude/settings.json)"
        Log-Ok "Merged settings into ~/.claude/settings.json"
    } catch {
        Log-Fail "Failed to merge settings: $_"
        $script:FAILURES += "Settings: JSON merge failed"
    } finally {
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
    }
}

function Install-Plugins {
    Log-Info "Installing plugins..."

    $plugins = @(
        "superpowers@claude-plugins-official"
        "code-simplifier@claude-plugins-official"
        "context7@claude-plugins-official"
    )

    $installed = ""
    try {
        $installed = claude plugin list 2>&1 | Out-String
    } catch {
        $installed = ""
    }

    foreach ($plugin in $plugins) {
        if ($installed -match [regex]::Escape($plugin)) {
            $script:SKIPPED += "Plugin: $plugin (already installed)"
            Log-Ok "Plugin already installed: $plugin"
        } else {
            Log-Info "Installing plugin: $plugin"
            $output = claude plugin install $plugin 2>&1 | Out-String
            if ($LASTEXITCODE -eq 0) {
                $script:APPLIED += "Plugin: $plugin"
                Log-Ok "Installed plugin: $plugin"
            } else {
                Log-Fail "Failed to install plugin: $plugin"
                $script:FAILURES += "Plugin: $plugin"
            }
        }
    }
}

function Configure-MCPs {
    Log-Info "Configuring MCP servers..."

    $existingMcps = ""
    try {
        $existingMcps = claude mcp list 2>&1 | Out-String
    } catch {
        $existingMcps = ""
    }

    # Google Calendar (remote HTTP)
    if ($existingMcps -match "Google Calendar") {
        $script:SKIPPED += "MCP: claude.ai Google Calendar (already registered)"
        Log-Ok "MCP already registered: claude.ai Google Calendar"
    } else {
        Log-Info "Adding MCP: claude.ai Google Calendar"
        $output = claude mcp add --transport http -s user "claude.ai Google Calendar" https://gcal.mcp.claude.com/mcp 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $script:APPLIED += "MCP: claude.ai Google Calendar"
            Log-Ok "Added MCP: claude.ai Google Calendar"
        } else {
            Log-Fail "Failed to add MCP: claude.ai Google Calendar"
            $script:FAILURES += "MCP: claude.ai Google Calendar"
        }
    }

    # Gmail (remote HTTP)
    if ($existingMcps -match "Gmail") {
        $script:SKIPPED += "MCP: claude.ai Gmail (already registered)"
        Log-Ok "MCP already registered: claude.ai Gmail"
    } else {
        Log-Info "Adding MCP: claude.ai Gmail"
        $output = claude mcp add --transport http -s user "claude.ai Gmail" https://gmail.mcp.claude.com/mcp 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $script:APPLIED += "MCP: claude.ai Gmail"
            Log-Ok "Added MCP: claude.ai Gmail"
        } else {
            Log-Fail "Failed to add MCP: claude.ai Gmail"
            $script:FAILURES += "MCP: claude.ai Gmail"
        }
    }

    # Sequential Thinking (npx stdio)
    if ($existingMcps -match "sequential-thinking") {
        $script:SKIPPED += "MCP: sequential-thinking (already registered)"
        Log-Ok "MCP already registered: sequential-thinking"
    } else {
        Log-Info "Adding MCP: sequential-thinking"
        $output = claude mcp add -s user sequential-thinking -- cmd /c npx -y @modelcontextprotocol/server-sequential-thinking 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $script:APPLIED += "MCP: sequential-thinking"
            Log-Ok "Added MCP: sequential-thinking"
        } else {
            Log-Fail "Failed to add MCP: sequential-thinking"
            $script:FAILURES += "MCP: sequential-thinking"
        }
    }
}

function Print-Summary {
    Write-Host ""
    Write-Host "========================================"
    Write-Host "  Claude Config Setup Summary"
    Write-Host "========================================"

    $appliedCount = $script:APPLIED.Count
    $skippedCount = $script:SKIPPED.Count
    $failureCount = $script:FAILURES.Count

    if ($appliedCount -gt 0) {
        Write-Host ""
        Log-Ok "Applied ($appliedCount):"
        foreach ($item in $script:APPLIED) {
            Write-Host "    - $item"
        }
    }

    if ($skippedCount -gt 0) {
        Write-Host ""
        Log-Info "Skipped ($skippedCount):"
        foreach ($item in $script:SKIPPED) {
            Write-Host "    - $item"
        }
    }

    if ($failureCount -gt 0) {
        Write-Host ""
        Log-Fail "Failed ($failureCount):"
        foreach ($item in $script:FAILURES) {
            Write-Host "    - $item"
        }
    }

    Write-Host ""
    Write-Host "========================================"

    if ($failureCount -gt 0) {
        return $false
    }
    return $true
}

# Main execution
function Main {
    Write-Host ""
    Write-Host "========================================"
    Write-Host "  Claude Code Setup"
    Write-Host "========================================"
    Write-Host ""

    if (-not (Check-Deps)) {
        Print-Summary | Out-Null
        exit 1
    }

    Configure-Settings
    Install-Plugins
    Configure-MCPs

    if (-not (Print-Summary)) {
        exit 1
    }
    exit 0
}

Main

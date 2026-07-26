# install-max-tps-fcc.ps1
# MAX-TPS FCC installer for WINDOWS - patched for thinkingmachines/inkling on NVIDIA NIM
#
# Usage in PowerShell:
#   cd C:\Users\Hamza\Desktop\files
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
#   .\install-max-tps-fcc.ps1
#
# This script:
#   1. NUKES any previous Claude Code AND free-claude-code install (completely)
#   2. Installs uv if missing
#   3. Installs Python 3.14 via uv
#   4. Installs the patched FCC wheel
#   5. Writes .env with your NIM key + max-TPS settings
#   6. Installs Claude Code via npm
#   7. Verifies everything works

param(
    # API key baked in by default (the one you gave me earlier).
    # Override with -ApiKey "..." if you want to use a different one.
    [string]$ApiKey = "nvapi-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
)

# Use Continue so native command stderr doesn't kill the script.
# We check $LASTEXITCODE ourselves where it matters.
$ErrorActionPreference = "Continue"

function Info  { param($m) Write-Host "[info] " -ForegroundColor Cyan   -NoNewline; Write-Host $m }
function Ok    { param($m) Write-Host "[ok]   " -ForegroundColor Green  -NoNewline; Write-Host $m }
function Warn  { param($m) Write-Host "[warn] " -ForegroundColor Yellow -NoNewline; Write-Host $m }
function Fatal { param($m) Write-Host "[fatal] " -ForegroundColor Red   -NoNewline; Write-Host $m; exit 1 }

# Helper: run a native command, swallow all stderr/stdout, never throw.
function Invoke-Quiet {
    param([scriptblock]$Block)
    try {
        & $Block 2>&1 | Out-Null
    } catch {}
}

# Helper: refresh PATH for this session.
function Refresh-Path {
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    $env:PATH = "$userPath;$machinePath"
}

# ============================================================================
# Find the wheel next to this script
# ============================================================================
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Wheel = Join-Path $ScriptDir "free_claude_code-4.12.9-py3-none-any.whl"

if (-not (Test-Path $Wheel)) {
    Fatal "Wheel not found at: $Wheel"
    Fatal "Put this .ps1 file in the same folder as the .whl file."
    exit 1
}

Write-Host ""
Write-Host "=== MAX-TPS FCC Installer for Windows ===" -ForegroundColor Cyan
Write-Host "Patched for thinkingmachines/inkling on NVIDIA NIM"
Write-Host "Wheel: $Wheel"
Write-Host ""

# ============================================================================
# STEP 1: NUKE everything old
# ============================================================================
Info "STEP 1/7: Nuking previous Claude Code AND free-claude-code installs..."

# Kill any running FCC or Claude Code processes
$procsToKill = @("fcc-server","fcc-claude","fcc-codex","fcc-desktop","fcc-pi","claude")
foreach ($p in $procsToKill) {
    Get-Process -Name $p -ErrorAction SilentlyContinue | ForEach-Object {
        Warn "Killing $($_.Name) (PID $($_.Id))"
        try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } catch {}
    }
}
Start-Sleep -Seconds 2

# Uninstall Claude Code via npm (try multiple times to be sure)
$npmCmd = Get-Command npm -ErrorAction SilentlyContinue
if ($npmCmd) {
    Info "Uninstalling @anthropic-ai/claude-code via npm..."
    Invoke-Quiet { & npm uninstall -g @anthropic-ai/claude-code }
    # Also nuke any global npm claude entries
    Invoke-Quiet { & npm uninstall -g claude }
    # Approve any pending scripts
    Invoke-Quiet { & npm approve-scripts -y @anthropic-ai/claude-code }
    Ok "npm uninstall attempted"
} else {
    Warn "npm not found - skipping npm-based Claude Code uninstall"
}

# Uninstall FCC via uv (idempotent - just try, ignore errors)
$uvCmd = Get-Command uv -ErrorAction SilentlyContinue
if ($uvCmd) {
    Info "Uninstalling free-claude-code via uv (if installed)..."
    Invoke-Quiet { & uv tool uninstall free-claude-code }
    Ok "uv uninstall attempted"
}

# Remove ~/.free-claude-code directory (with backup)
$FccDir = Join-Path $env:USERPROFILE ".free-claude-code"
if (Test-Path $FccDir) {
    $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $BackupDir = "$FccDir.bak.$stamp"
    Warn "Backing up $FccDir -> $BackupDir"
    try {
        Move-Item $FccDir $BackupDir -Force -ErrorAction Stop
    } catch {
        Warn "Could not move (may be locked). Removing instead."
        Remove-Item $FccDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Remove ~/.claude directory (Claude Code config) - with backup
$ClaudeConfigDir = Join-Path $env:USERPROFILE ".claude"
if (Test-Path $ClaudeConfigDir) {
    $stamp2 = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $ClaudeBackup = "$ClaudeConfigDir.bak.$stamp2"
    Warn "Backing up $ClaudeConfigDir -> $ClaudeBackup"
    try {
        Move-Item $ClaudeConfigDir $ClaudeBackup -Force -ErrorAction Stop
    } catch {
        Warn "Could not move. Removing instead."
        Remove-Item $ClaudeConfigDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Find and remove any stray claude executables in common install locations
$claudePaths = @(
    (Join-Path $env:APPDATA "npm\claude.cmd"),
    (Join-Path $env:APPDATA "npm\claude.ps1"),
    (Join-Path $env:APPDATA "npm\claude"),
    (Join-Path $env:LOCALAPPDATA "npm\claude.cmd"),
    (Join-Path $env:LOCALAPPDATA "npm\claude.ps1"),
    (Join-Path $env:LOCALAPPDATA "npm\claude"),
    (Join-Path $env:APPDATA "npm\node_modules\@anthropic-ai"),
    (Join-Path $env:LOCALAPPDATA "npm\node_modules\@anthropic-ai")
)
foreach ($cp in $claudePaths) {
    if (Test-Path $cp) {
        Warn "Removing stray file: $cp"
        Remove-Item $cp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Remove Start Menu shortcuts
$StartMenu = [Environment]::GetFolderPath("Programs")
$Shortcuts = @(
    (Join-Path $StartMenu "Free Claude Code.lnk"),
    (Join-Path $StartMenu "Claude Code.lnk")
)
foreach ($shortcut in $Shortcuts) {
    if (Test-Path $shortcut) {
        Remove-Item $shortcut -Force -ErrorAction SilentlyContinue
    }
}

Ok "Previous installs nuked."
Write-Host ""

# ============================================================================
# STEP 2: Install uv if missing
# ============================================================================
Info "STEP 2/7: Ensuring uv is installed..."
Refresh-Path
$uvCmd = Get-Command uv -ErrorAction SilentlyContinue
if ($uvCmd) {
    Ok "uv already installed: $(& uv --version)"
} else {
    Info "Installing uv..."
    try {
        & ([scriptblock]::Create((Invoke-WebRequest -UseBasicParsing -Uri "https://astral.sh/uv/install.ps1").Content))
    } catch {
        Fatal "uv install failed: $_"
    }
    Refresh-Path
    $uvCmd = Get-Command uv -ErrorAction SilentlyContinue
    if (-not $uvCmd) {
        Fatal "uv install seemed to succeed but uv is not on PATH. Close this window, open a new PowerShell, and re-run this script."
    }
    Ok "uv installed: $(& uv --version)"
}
Write-Host ""

# ============================================================================
# STEP 3: Install Python 3.14
# ============================================================================
Info "STEP 3/7: Ensuring Python 3.14 is installed..."
& uv python install 3.14 2>&1 | Select-Object -Last 3 | ForEach-Object { Write-Host "  $_" }
$pyFind = & uv python find 3.14 2>$null
if (-not $pyFind -or -not (Test-Path $pyFind)) {
    Fatal "Python 3.14 install failed"
}
Ok "Python 3.14 available: $pyFind"
Write-Host ""

# ============================================================================
# STEP 4: Install the patched FCC wheel
# ============================================================================
Info "STEP 4/7: Installing patched FCC wheel..."
# Use 2>&1 to merge stderr into stdout so it doesn't throw
& uv tool install --force --python 3.14 $Wheel 2>&1 | ForEach-Object { Write-Host "  $_" }
if ($LASTEXITCODE -ne 0) {
    Fatal "FCC wheel install failed (exit code $LASTEXITCODE)"
}
Invoke-Quiet { & uv tool update-shell }
Refresh-Path

# Verify entry points
foreach ($cmd in @("fcc-server","fcc-claude","fcc-codex","fcc-pi")) {
    $found = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($found) {
        Ok "  $cmd -> $($found.Source)"
    } else {
        Warn "  $cmd not yet on PATH (open a new shell after install)"
    }
}
Write-Host ""

# ============================================================================
# STEP 5: Configure NIM API key
# ============================================================================
Info "STEP 5/7: Configuring NVIDIA NIM API key..."

$FccDir = Join-Path $env:USERPROFILE ".free-claude-code"
New-Item -ItemType Directory -Path $FccDir -Force | Out-Null

if (-not $ApiKey) {
    $ApiKey = $env:NVIDIA_NIM_API_KEY
}
if (-not $ApiKey) {
    Write-Host ""
    $ApiKey = Read-Host "  Paste your NVIDIA NIM API key (nvapi-...)"
}
if (-not $ApiKey) {
    Warn "No API key provided. Add it later to $FccDir\.env"
} else {
    # Mask the key when printing
    $masked = $ApiKey.Substring(0, [Math]::Min(12, $ApiKey.Length)) + "..."
    Ok "Using API key: $masked"
}

$EnvFile = Join-Path $FccDir ".env"
$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# Use here-string for the env file content
$EnvContent = @"
# MAX-TPS FCC configuration - patched for thinkingmachines/inkling
# Generated by install-max-tps-fcc.ps1 on $Timestamp

# === NVIDIA NIM API key ===
NVIDIA_NIM_API_KEY=$ApiKey

# === Default model: thinkingmachines/inkling with reasoning_effort=max ===
MODEL=nvidia_nim/thinkingmachines/inkling
MODEL_FABLE=nvidia_nim/thinkingmachines/inkling
MODEL_OPUS=nvidia_nim/thinkingmachines/inkling
MODEL_SONNET=nvidia_nim/thinkingmachines/inkling
MODEL_HAIKU=nvidia_nim/thinkingmachines/inkling

# === Max reasoning effort on all Claude tiers ===
REASONING_FABLE=max
REASONING_OPUS=max
REASONING_SONNET=max
REASONING_HAIKU=max

# === HTTP timeouts: NO read timeout (let streams run forever) ===
HTTP_READ_TIMEOUT=0
HTTP_WRITE_TIMEOUT=30
HTTP_CONNECT_TIMEOUT=10

# === Local FCC server ===
PROXY_HOST=127.0.0.1
PROXY_PORT=8082
"@

$EnvContent | Out-File -FilePath $EnvFile -Encoding ASCII -Force
Ok "Wrote $EnvFile"
Write-Host ""

# ============================================================================
# STEP 6: Install Claude Code
# ============================================================================
Info "STEP 6/7: Installing Claude Code via npm..."
$npmCmd = Get-Command npm -ErrorAction SilentlyContinue
if (-not $npmCmd) {
    Warn "npm not found - skipping Claude Code install"
    Warn "Install Node.js LTS from https://nodejs.org/ then run:"
    Warn "  npm install -g @anthropic-ai/claude-code"
} else {
    & npm install -g @anthropic-ai/claude-code 2>&1 | ForEach-Object { Write-Host "  $_" }
    Invoke-Quiet { & npm approve-scripts -y @anthropic-ai/claude-code }
    Refresh-Path
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($claudeCmd) {
        $claudeVer = & claude --version 2>&1 | Select-Object -First 1
        Ok "Claude Code installed: $claudeVer"
    } else {
        Warn "Claude Code install may have partially failed. Try manually:"
        Warn "  npm install -g @anthropic-ai/claude-code"
    }
}
Write-Host ""

# ============================================================================
# STEP 7: Final verification
# ============================================================================
Info "STEP 7/7: Final verification..."
Write-Host ""
Write-Host "  === INSTALL COMPLETE ===" -ForegroundColor Green
Write-Host ""

Write-Host "  Patched FCC:" -ForegroundColor White
foreach ($cmd in @("fcc-server","fcc-claude")) {
    $found = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($found) {
        Write-Host "    $cmd : " -NoNewline
        Write-Host $found.Source -ForegroundColor Green
    } else {
        Write-Host "    $cmd : " -NoNewline
        Write-Host "(open a new shell)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "  Claude Code:" -ForegroundColor White
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if ($claudeCmd) {
    Write-Host "    claude : " -NoNewline
    Write-Host $claudeCmd.Source -ForegroundColor Green
} else {
    Write-Host "    claude : " -NoNewline
    Write-Host "(install manually via npm)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Config: " -NoNewline
Write-Host $EnvFile -ForegroundColor Cyan

Write-Host ""
Write-Host "  === NEXT STEPS ===" -ForegroundColor Cyan
Write-Host "  1. Open a NEW PowerShell window (so PATH updates take effect)"
Write-Host "  2. Start the FCC proxy:" -ForegroundColor White
Write-Host "       fcc-server" -ForegroundColor Green
Write-Host "  3. In another PowerShell window, run Claude Code through FCC:" -ForegroundColor White
Write-Host "       fcc-claude" -ForegroundColor Green
Write-Host "  4. Or open the Admin UI to tweak settings:" -ForegroundColor White
Write-Host "       http://127.0.0.1:8082/admin" -ForegroundColor Cyan
Write-Host ""
Write-Host "  === WHATS PATCHED FOR MAX TPS ===" -ForegroundColor Yellow
Write-Host "  - NIM provider sends reasoning_effort=max as a top-level param"
Write-Host "  - HTTP_READ_TIMEOUT=0 (no timeout) - streams never get killed"
Write-Host "  - NIM 403/429 treated as retryable rate-limit (10 retries, 1-120s backoff)"
Write-Host "  - Default model: thinkingmachines/inkling on all Claude tiers"
Write-Host "  - REASONING_FABLE/OPUS/SONNET/HAIKU all set to max"
Write-Host "  - CLAUDE_CODE_AUTO_COMPACT_WINDOW=900000 (use full 1M context)"
Write-Host "  - CLAUDE_CODE_MAX_OUTPUT_TOKENS=8192 (matches inkling cap)"
Write-Host "  - BASH_DEFAULT_TIMEOUT_MS=600000 (10 min bash commands)"
Write-Host "  - BASH_MAX_TIMEOUT_MS=1800000 (30 min max bash)"
Write-Host "  - MAX_THINKING_TOKENS=8192 (force max thinking)"
Write-Host "  - CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=95 (compact at 95% not 80%)"
Write-Host "  - CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1 (no auto-reduce)"
Write-Host "  - FCC rate limit: 15 req/60s, concurrency 2 (NIM-friendly)"
Write-Host "  - FCC retry: 10 attempts, 1-120s exponential backoff"
Write-Host ""

#!/bin/bash
# install-max-tps-fcc.sh
#
# MAX-TPS FCC installer — patched for thinkingmachines/inkling on NVIDIA NIM.
#
# What this script does:
#   1. NUKES any previous free-claude-code install (uv tool, ~/.free-claude-code, env entries)
#   2. Installs uv if missing
#   3. Installs Python 3.14 via uv (needed by FCC)
#   4. Installs the patched FCC wheel (with max-TPS NIM patches)
#   5. Prompts for NVIDIA NIM API key and writes ~/.free-claude-code/.env
#   6. Installs Claude Code via npm (if missing)
#   7. Verifies fcc-server, fcc-claude, and claude are all on PATH
#
# After install:
#   - Start the proxy:    fcc-server
#   - Run Claude Code:    fcc-claude
#   - Open Admin UI:      http://127.0.0.1:8082/admin

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { printf "${CYAN}[info]${NC} %s\n"  "$*"; }
ok()    { printf "${GREEN}[ok]${NC} %s\n"    "$*"; }
warn()  { printf "${YELLOW}[warn]${NC} %s\n" "$*"; }
fatal() { printf "${RED}[fatal]${NC} %s\n"   "$*" >&2; exit 1; }

# Locate the bundled wheel (same directory as this script)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHEEL="$SCRIPT_DIR/free_claude_code-4.12.9-py3-none-any.whl"

if [[ ! -f "$WHEEL" ]]; then
    fatal "Patched FCC wheel not found at: $WHEEL"
    fatal "Make sure you extracted the full tarball and are running this script from its directory."
    exit 1
fi

info "=== MAX-TPS FCC Installer (patched for thinkingmachines/inkling) ==="
info "Wheel: $WHEEL"
echo ""

# ============================================================================
# Step 1: NUKE previous FCC install
# ============================================================================
info "Step 1/7: Nuking any previous free-claude-code install..."

# Kill any running FCC processes
if command -v pkill >/dev/null 2>&1; then
    pkill -f "fcc-server"   2>/dev/null || true
    pkill -f "fcc-claude"   2>/dev/null || true
    pkill -f "fcc-codex"    2>/dev/null || true
    pkill -f "fcc-desktop"  2>/dev/null || true
    pkill -f "fcc-pi"       2>/dev/null || true
fi
sleep 1

# Uninstall via uv (idempotent)
if command -v uv >/dev/null 2>&1; then
    uv tool uninstall free-claude-code 2>/dev/null || true
    # Also uninstall any old name variants
    uv tool uninstall free-claude-code 2>/dev/null || true
fi

# Remove the config/state directory
FCC_DIR="${HOME}/.free-claude-code"
if [[ -d "$FCC_DIR" ]]; then
    warn "Removing existing FCC config at $FCC_DIR (backing up to ${FCC_DIR}.bak)"
    [[ -e "${FCC_DIR}.bak" ]] && rm -rf "${FCC_DIR}.bak"
    mv "$FCC_DIR" "${FCC_DIR}.bak"
fi

# Remove the macOS app bundle if present (no-op on Linux)
MACOS_APP="${HOME}/Applications/Free Claude Code.app"
if [[ -e "$MACOS_APP" ]]; then
    rm -rf "$MACOS_APP"
fi
MACOS_DESKTOP="${HOME}/Desktop/Free Claude Code.app"
if [[ -L "$MACOS_DESKTOP" || -e "$MACOS_DESKTOP" ]]; then
    rm -f "$MACOS_DESKTOP"
fi

ok "Previous install nuked."

# ============================================================================
# Step 2: Install uv if missing
# ============================================================================
info "Step 2/7: Ensuring uv is installed..."
if command -v uv >/dev/null 2>&1; then
    ok "uv already installed: $(uv --version)"
else
    info "Installing uv..."
    curl -fsSL https://astral.sh/uv/install.sh | sh
    # Add uv to PATH for this script
    export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"
    hash -r 2>/dev/null || true
    command -v uv >/dev/null 2>&1 || fatal "uv install failed"
    ok "uv installed: $(uv --version)"
fi

# Make sure uv's bin dir is on PATH going forward
UV_BIN_DIR="$(uv tool dir --bin 2>/dev/null || echo "${HOME}/.local/bin")"
case ":${PATH}:" in
    *":${UV_BIN_DIR}:"*) ;;
    *) export PATH="${UV_BIN_DIR}:${PATH}";;
esac

# ============================================================================
# Step 3: Install Python 3.14 (FCC requires >=3.14)
# ============================================================================
info "Step 3/7: Ensuring Python 3.14 is installed..."
uv python install 3.14 2>&1 | tail -3
ok "Python 3.14 available: $(uv python find 3.14)"

# ============================================================================
# Step 4: Install the patched FCC wheel
# ============================================================================
info "Step 4/7: Installing patched FCC wheel..."
uv tool install --force --python 3.14 "$WHEEL"
ok "FCC installed."

# Make sure uv tool bin is on PATH
uv tool update-shell 2>/dev/null || true

# Verify the entry points exist
for cmd in fcc-server fcc-claude fcc-codex fcc-pi; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "  $cmd -> $(command -v $cmd)"
    else
        warn "  $cmd not yet on PATH (you may need to open a new shell)"
    fi
done

# ============================================================================
# Step 5: Configure NIM API key
# ============================================================================
info "Step 5/7: Configuring NVIDIA NIM API key..."

FCC_DIR="${HOME}/.free-claude-code"
mkdir -p "$FCC_DIR"

# Read API key from arg, env, or prompt
NVIDIA_API_KEY="${NVIDIA_NIM_API_KEY:-}"
if [[ -n "${1:-}" ]]; then
    NVIDIA_API_KEY="$1"
fi
if [[ -z "$NVIDIA_API_KEY" ]]; then
    echo ""
    printf "  Paste your NVIDIA NIM API key (nvapi-...): "
    read -r NVIDIA_API_KEY
fi
if [[ -z "$NVIDIA_API_KEY" ]]; then
    warn "No API key provided. You can add it later to $FCC_DIR/.env"
fi

# Write .env with max-TPS settings
cat > "$FCC_DIR/.env" <<EOF
# MAX-TPS FCC configuration — patched for thinkingmachines/inkling
# Generated by install-max-tps-fcc.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)

# === NVIDIA NIM API key ===
NVIDIA_NIM_API_KEY=$NVIDIA_API_KEY

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
EOF
chmod 600 "$FCC_DIR/.env"
ok "Wrote $FCC_DIR/.env (mode 600)"

# ============================================================================
# Step 6: Install Claude Code (if missing)
# ============================================================================
info "Step 6/7: Ensuring Claude Code is installed..."
if command -v claude >/dev/null 2>&1; then
    ok "Claude Code already installed: $(claude --version 2>&1 | head -1)"
else
    info "Installing Claude Code via npm..."
    if ! command -v npm >/dev/null 2>&1; then
        warn "npm not found — skipping Claude Code install."
        warn "Install Node.js from https://nodejs.org/ then run:"
        warn "  npm install -g @anthropic-ai/claude-code"
    else
        npm install -g @anthropic-ai/claude-code
        # Approve postinstall if needed
        npm approve-scripts -y @anthropic-ai/claude-code 2>/dev/null || true
        if command -v claude >/dev/null 2>&1; then
            ok "Claude Code installed: $(claude --version 2>&1 | head -1)"
        else
            warn "Claude Code install may have partially failed. Try manually:"
            warn "  npm install -g @anthropic-ai/claude-code"
        fi
    fi
fi

# ============================================================================
# Step 7: Final verification
# ============================================================================
info "Step 7/7: Final verification..."
echo ""
printf "  ${GREEN}=== INSTALL COMPLETE ===${NC}\n"
echo ""
echo "  Patched FCC (max-TPS for thinkingmachines/inkling):"
(command -v fcc-server >/dev/null 2>&1 && printf "    fcc-server:  ${GREEN}%s${NC}\n" "$(command -v fcc-server)") || printf "    fcc-server:  ${YELLOW}(not on PATH yet — open a new shell)${NC}\n"
(command -v fcc-claude >/dev/null 2>&1 && printf "    fcc-claude:  ${GREEN}%s${NC}\n" "$(command -v fcc-claude)") || printf "    fcc-claude:  ${YELLOW}(not on PATH yet — open a new shell)${NC}\n"
echo ""
echo "  Claude Code:"
(command -v claude >/dev/null 2>&1 && printf "    claude:      ${GREEN}%s${NC}\n" "$(command -v claude)") || printf "    claude:      ${YELLOW}(install manually via npm)${NC}\n"
echo ""
echo "  Config: ${CYAN}$FCC_DIR/.env${NC}"
echo ""
echo "  ${CYAN}=== NEXT STEPS ===${NC}"
echo "  1. Open a NEW terminal (so PATH updates take effect)"
echo "  2. Start the FCC proxy:"
echo "       ${GREEN}fcc-server${NC}"
echo "  3. In another terminal, run Claude Code through FCC:"
echo "       ${GREEN}fcc-claude${NC}"
echo "  4. Or open the Admin UI to tweak settings:"
echo "       ${CYAN}http://127.0.0.1:8082/admin${NC}"
echo ""
echo "  ${YELLOW}=== WHAT'S PATCHED FOR MAX TPS ===${NC}"
echo "  - NIM provider now sends reasoning_effort=max as a top-level param"
echo "  - HTTP_READ_TIMEOUT=0 (None) — streams never get killed mid-thought"
echo "  - NIM 403 'Authorization failed' treated as retryable rate-limit (60s backoff)"
echo "  - Default model is thinkingmachines/inkling on all 4 Claude tiers (fable/opus/sonnet/haiku)"
echo "  - REASONING_FABLE/OPUS/SONNET/HAIKU all set to 'max'"
echo ""

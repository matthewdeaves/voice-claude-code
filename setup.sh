#!/bin/bash
#
# Voice Mode Setup & Update Script
# One-shot setup for local voice mode with Claude Code
#
# IDEMPOTENT: Safe to run multiple times
# UPDATES: Always installs latest voice-mode version
#
# Run this script to:
#   - First time: Install everything from scratch
#   - Subsequent runs: Update to latest version + verify services
#
# Optimizations: Auto-detects CPU cores, uses local-only mode
#

# Don't exit on error - we handle errors gracefully
set +e

# Fail gracefully on SIGINT/SIGTERM
trap 'echo -e "\n${RED}Setup interrupted${NC}"; exit 1' INT TERM

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Configuration
VOICEMODE_DIR="$HOME/.voicemode"
WHISPER_DIR="$VOICEMODE_DIR/services/whisper"
WHISPER_BUILD="$WHISPER_DIR/build"
KOKORO_DIR="$VOICEMODE_DIR/services/kokoro"
UV_TOOLS_DIR="$HOME/.local/share/uv/tools"
CPU_CORES=$(nproc 2>/dev/null || echo 6)

# Get script directory for template files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"

echo -e "${BLUE}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         Voice Mode Complete Setup for Claude Code            ║"
echo "║              Local STT (Whisper) + TTS (Kokoro)              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "Detected: $CPU_CORES CPU cores, optimizing for this machine..."
echo ""

# -----------------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------------
print_ok()    { echo -e "${GREEN}[✓]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
print_err()   { echo -e "${RED}[✗]${NC} $1"; }
print_step()  { echo -e "\n${BLUE}${BOLD}[$1]${NC} $2\n"; }
print_skip()  { echo -e "${GREEN}[✓]${NC} $1 ${YELLOW}(already done)${NC}"; }

command_exists() { command -v "$1" &> /dev/null; }

# Check if voicemode is working (not just installed)
voicemode_works() {
    command_exists voicemode && voicemode --version &>/dev/null
}

# -----------------------------------------------------------------------------
# STEP 1: System Dependencies
# -----------------------------------------------------------------------------
print_step "1/9" "Checking system dependencies..."

DEPS="curl git cmake make gcc g++ ffmpeg python3 python3-pip python3-venv python3-dev libasound2-dev libportaudio2"
MISSING=""
for dep in $DEPS; do
    if ! dpkg -l "$dep" &>/dev/null 2>&1; then
        MISSING="$MISSING $dep"
    fi
done

if [ -n "$MISSING" ]; then
    echo "Installing:$MISSING"
    sudo apt-get update -qq
    sudo apt-get install -y -qq $MISSING
    print_ok "System dependencies installed"
else
    print_skip "System dependencies ready"
fi

# -----------------------------------------------------------------------------
# STEP 2: Install uv (fast Python package manager)
# -----------------------------------------------------------------------------
print_step "2/9" "Setting up uv package manager..."

export PATH="$HOME/.local/bin:$PATH"

if ! command_exists uv; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    print_ok "uv installed"
else
    print_skip "uv ready"
fi

# -----------------------------------------------------------------------------
# STEP 3: Install Voice Mode (with broken install recovery)
# -----------------------------------------------------------------------------
print_step "3/9" "Setting up Voice Mode..."

NEED_INSTALL=false

# Check if voicemode works
if voicemode_works; then
    # Check if whisper and kokoro are installed
    if [ -f "$WHISPER_BUILD/bin/whisper-server" ] && [ -d "$KOKORO_DIR" ]; then
        print_skip "Voice Mode already installed and working"
    else
        print_warn "Voice Mode installed but services missing, will reinstall"
        NEED_INSTALL=true
    fi
else
    NEED_INSTALL=true

    # Clean up broken uv tool installation if it exists
    if [ -d "$UV_TOOLS_DIR/voice-mode" ]; then
        print_warn "Found broken voice-mode installation, cleaning up..."
        rm -rf "$UV_TOOLS_DIR/voice-mode" 2>/dev/null || sudo rm -rf "$UV_TOOLS_DIR/voice-mode"
    fi
fi

if $NEED_INSTALL; then
    echo "Running voice-mode installer..."

    # Install with --yes (non-interactive) and --force (overwrite existing)
    # Capture output to filter noisy errors that aren't real problems
    INSTALL_OUTPUT=$(uvx voice-mode-install --yes --force 2>&1) || true

    # Check if installation actually succeeded by looking for key components
    if [ -f "$WHISPER_BUILD/bin/whisper-server" ] && [ -d "$KOKORO_DIR" ]; then
        print_ok "Voice Mode installed"
    elif [ -f "$WHISPER_BUILD/bin/whisper-server" ]; then
        print_ok "Whisper installed (Kokoro may need separate install)"
    else
        print_warn "Installer output:"
        echo "$INSTALL_OUTPUT" | tail -20
        print_err "Whisper server not found - may need manual intervention"
    fi
fi

# Refresh PATH and check again
export PATH="$HOME/.local/bin:$PATH"
hash -r 2>/dev/null || true

# -----------------------------------------------------------------------------
# STEP 4: Configure System Library Paths (requires sudo)
# -----------------------------------------------------------------------------
print_step "4/9" "Configuring shared library paths..."

if [ -d "$WHISPER_BUILD/ggml/src" ]; then
    # Check if already configured
    if [ -f /etc/ld.so.conf.d/voicemode.conf ] && ldconfig -p | grep -q libggml; then
        print_skip "Library paths already configured"
    else
        echo "Adding whisper.cpp libraries to system path..."
        sudo tee /etc/ld.so.conf.d/voicemode.conf > /dev/null << EOF
# Voice Mode - whisper.cpp shared libraries
$WHISPER_BUILD/ggml/src
$WHISPER_BUILD/src
EOF
        sudo ldconfig

        if ldconfig -p | grep -q libggml; then
            print_ok "Library paths configured"
        else
            print_warn "Libraries configured but verification uncertain"
        fi
    fi
else
    print_warn "Whisper build not found at $WHISPER_BUILD"
fi

# -----------------------------------------------------------------------------
# STEP 5: Patch Whisper Start Script with Optimizations
# -----------------------------------------------------------------------------
print_step "5/9" "Configuring Whisper server..."

START_SCRIPT="$WHISPER_DIR/bin/start-whisper-server.sh"

if [ -d "$WHISPER_DIR" ]; then
    if ! mkdir -p "$(dirname "$START_SCRIPT")" 2>/dev/null; then
        print_err "Failed to create directory for start script"
    fi

    cat > "$START_SCRIPT" << 'SCRIPT_CONTENT'
#!/bin/bash
# Whisper Server Start Script (Optimized)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHISPER_DIR="$(dirname "$SCRIPT_DIR")"
VOICEMODE_DIR="$HOME/.voicemode"

# Set library paths
export LD_LIBRARY_PATH="$WHISPER_DIR/build/ggml/src:$WHISPER_DIR/build/src:${LD_LIBRARY_PATH:-}"

# Use /tmp for temp files (OS cleans up automatically)
cd /tmp

# Source config
[ -f "$VOICEMODE_DIR/voicemode.env" ] && source "$VOICEMODE_DIR/voicemode.env"

# Settings with optimized defaults
MODEL_NAME="${VOICEMODE_WHISPER_MODEL:-base}"
MODEL_PATH="$WHISPER_DIR/models/ggml-$MODEL_NAME.bin"
WHISPER_PORT="${VOICEMODE_WHISPER_PORT:-2022}"
WHISPER_THREADS="${VOICEMODE_WHISPER_THREADS:-$(nproc)}"

# Fallback model search
if [ ! -f "$MODEL_PATH" ]; then
    MODEL_PATH=$(ls -1 "$WHISPER_DIR/models/"ggml-*.bin 2>/dev/null | head -1)
    [ -z "$MODEL_PATH" ] && { echo "No model found"; exit 1; }
fi

# Find server binary
SERVER_BIN="$WHISPER_DIR/build/bin/whisper-server"
[ ! -f "$SERVER_BIN" ] && { echo "whisper-server not found"; exit 1; }

# Start with OpenAI-compatible API endpoint
# Note: Server uses current directory for temp files, so we cd to /tmp above
exec "$SERVER_BIN" \
    --host 0.0.0.0 \
    --port "$WHISPER_PORT" \
    --model "$MODEL_PATH" \
    --inference-path /v1/audio/transcriptions \
    --threads "$WHISPER_THREADS" \
    --convert
SCRIPT_CONTENT

    chmod +x "$START_SCRIPT"
    print_ok "Whisper start script configured ($CPU_CORES threads)"
else
    print_warn "Whisper directory not found, skipping start script"
fi

# -----------------------------------------------------------------------------
# STEP 6: Configure voicemode.env with optimizations
# -----------------------------------------------------------------------------
print_step "6/9" "Setting optimal configuration..."

ENV_FILE="$VOICEMODE_DIR/voicemode.env"

if [ -f "$ENV_FILE" ]; then
    # Check if already optimized (using silence threshold as marker)
    if grep -q "^VOICEMODE_SILENCE_THRESHOLD_MS=3000" "$ENV_FILE" 2>/dev/null; then
        print_skip "Configuration already optimized"
    else
        # Remove old optimization settings if they exist
        sed -i '/^VOICEMODE_WHISPER_THREADS=/d' "$ENV_FILE" 2>/dev/null
        sed -i '/^VOICEMODE_PREFER_LOCAL=/d' "$ENV_FILE" 2>/dev/null
        sed -i '/^VOICEMODE_ALWAYS_TRY_LOCAL=/d' "$ENV_FILE" 2>/dev/null
        sed -i '/^VOICEMODE_SILENCE_THRESHOLD_MS=/d' "$ENV_FILE" 2>/dev/null
        sed -i '/^VOICEMODE_MIN_RECORDING_DURATION=/d' "$ENV_FILE" 2>/dev/null
        sed -i '/^VOICEMODE_INITIAL_SILENCE_GRACE_PERIOD=/d' "$ENV_FILE" 2>/dev/null
        sed -i '/^# Optimizations for this machine/d' "$ENV_FILE" 2>/dev/null
        sed -i '/^# Voice conversation settings/d' "$ENV_FILE" 2>/dev/null

        cat >> "$ENV_FILE" << EOF

# Optimizations for this machine ($CPU_CORES cores)
VOICEMODE_WHISPER_THREADS=$CPU_CORES
VOICEMODE_PREFER_LOCAL=true
VOICEMODE_ALWAYS_TRY_LOCAL=true

# Voice conversation settings - give users more time to respond
VOICEMODE_SILENCE_THRESHOLD_MS=3000
VOICEMODE_MIN_RECORDING_DURATION=3.0
VOICEMODE_INITIAL_SILENCE_GRACE_PERIOD=2.0
EOF
        print_ok "Configuration optimized"
    fi
else
    print_warn "voicemode.env not found, skipping optimization"
fi

# -----------------------------------------------------------------------------
# STEP 7: Create Systemd User Services (for auto-start on login)
# -----------------------------------------------------------------------------
print_step "7/9" "Setting up systemd services for auto-start..."

SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_USER_DIR"

# Helper function to process template files
process_template() {
    local template="$1"
    local output="$2"
    sed -e "s|{{WHISPER_DIR}}|$WHISPER_DIR|g" \
        -e "s|{{WHISPER_BUILD}}|$WHISPER_BUILD|g" \
        -e "s|{{KOKORO_DIR}}|$KOKORO_DIR|g" \
        -e "s|{{HOME}}|$HOME|g" \
        "$template" > "$output"
}

# Create Whisper service from template
WHISPER_SERVICE="$SYSTEMD_USER_DIR/voicemode-whisper.service"
process_template "$TEMPLATES_DIR/voicemode-whisper.service" "$WHISPER_SERVICE"

# Create Kokoro service from template
KOKORO_SERVICE="$SYSTEMD_USER_DIR/voicemode-kokoro.service"
process_template "$TEMPLATES_DIR/voicemode-kokoro.service" "$KOKORO_SERVICE"

# Reload systemd user daemon
systemctl --user daemon-reload 2>/dev/null || true

# Enable services (start on login)
if [ -f "$WHISPER_SERVICE" ]; then
    systemctl --user enable voicemode-whisper.service 2>/dev/null && \
        print_ok "Whisper service enabled (auto-start on login)" || \
        print_warn "Could not enable Whisper service"
fi

if [ -f "$KOKORO_SERVICE" ]; then
    systemctl --user enable voicemode-kokoro.service 2>/dev/null && \
        print_ok "Kokoro service enabled (auto-start on login)" || \
        print_warn "Could not enable Kokoro service"
fi

# Enable lingering so services start even without login session
loginctl enable-linger "$USER" 2>/dev/null || true

# -----------------------------------------------------------------------------
# STEP 8: Enable and Start Services
# -----------------------------------------------------------------------------
print_step "8/9" "Starting services..."

# Always ensure exactly ONE whisper server with correct config
echo "Ensuring Whisper service..."

# Gracefully stop existing whisper processes, then force if needed
pkill -f whisper-server 2>/dev/null || true
sleep 1
pkill -9 -f whisper-server 2>/dev/null || true
sleep 1

# Start fresh with our script
if [ -x "$START_SCRIPT" ] && [ -x "$WHISPER_BUILD/bin/whisper-server" ]; then
    "$START_SCRIPT" &>/dev/null &

    # Wait for it to come up
    for i in {1..10}; do
        if curl -s -m 1 http://127.0.0.1:2022/ &>/dev/null; then
            print_ok "Whisper started"
            break
        fi
        sleep 1
    done

    # Verify it's responding
    if ! curl -s -m 1 http://127.0.0.1:2022/ &>/dev/null; then
        print_err "Whisper failed to start"
    fi
elif [ ! -x "$START_SCRIPT" ]; then
    print_err "Whisper start script not found or not executable"
else
    print_err "Whisper server binary not found at $WHISPER_BUILD/bin/whisper-server"
fi

# Ensure exactly ONE Kokoro server
echo "Ensuring Kokoro service..."

if curl -s -m 2 http://127.0.0.1:8880/health &>/dev/null; then
    print_ok "Kokoro already running"
else
    # Gracefully stop kokoro processes, then force if needed
    # Match kokoro server processes specifically (uvicorn on port 8880 or kokoro in path)
    pkill -f "uvicorn.*8880" 2>/dev/null || true
    pkill -f "$KOKORO_DIR" 2>/dev/null || true
    sleep 1
    pkill -9 -f "uvicorn.*8880" 2>/dev/null || true
    pkill -9 -f "$KOKORO_DIR" 2>/dev/null || true
    sleep 1

    # Start kokoro
    export PATH="$HOME/.local/bin:$PATH"
    if command -v voicemode &>/dev/null; then
        voicemode kokoro start &>/dev/null &
    elif [ -d "$KOKORO_DIR" ]; then
        cd "$KOKORO_DIR" && ./start-cpu.sh &>/dev/null &
    fi

    # Wait for it to come up
    echo "  Waiting for Kokoro..."
    for i in {1..15}; do
        if curl -s -m 2 http://127.0.0.1:8880/health &>/dev/null; then
            print_ok "Kokoro started"
            break
        fi
        sleep 1
    done

    if ! curl -s -m 2 http://127.0.0.1:8880/health &>/dev/null; then
        print_err "Kokoro failed to start"
    fi
fi

# Wait for services to fully initialize
sleep 2

# -----------------------------------------------------------------------------
# STEP 9: Verify Everything Works
# -----------------------------------------------------------------------------
print_step "9/9" "Verifying setup..."

ALL_OK=true

# Check Whisper process
if pgrep -f whisper-server &>/dev/null; then
    print_ok "Whisper process running"

    # Test API endpoint
    RESP=$(curl -s -m 5 -X POST http://127.0.0.1:2022/v1/audio/transcriptions \
           -F "file=@/dev/null" 2>&1 || echo "connection_failed")
    if echo "$RESP" | grep -qi "error\|Error"; then
        print_ok "Whisper API endpoint OK (OpenAI-compatible)"
    elif echo "$RESP" | grep -qi "connection_failed\|refused"; then
        print_warn "Whisper running but API not responding yet"
        ALL_OK=false
    else
        print_warn "Whisper API response unexpected: $RESP"
        ALL_OK=false
    fi
else
    print_err "Whisper not running"
    ALL_OK=false
fi

# Check Kokoro - primarily via health endpoint (most reliable)
if curl -s -m 2 http://127.0.0.1:8880/health &>/dev/null; then
    print_ok "Kokoro TTS running"
elif pgrep -f "kokoro" &>/dev/null || pgrep -f "uvicorn.*8880" &>/dev/null; then
    print_warn "Kokoro process found but health endpoint not responding"
    ALL_OK=false
else
    print_warn "Kokoro not detected"
    ALL_OK=false
fi

# Check MCP server config (only if claude command exists)
if command_exists claude; then
    if claude mcp list 2>/dev/null | grep -q voicemode; then
        print_ok "MCP server configured"
    else
        echo "Adding VoiceMode MCP server to Claude Code..."
        claude mcp add --scope user voicemode -- uvx --refresh voice-mode 2>/dev/null || true
        print_ok "MCP server added"
    fi
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════════${NC}"

if $ALL_OK; then
    echo -e "${GREEN}${BOLD}                    Setup Complete!                           ${NC}"
    echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BLUE}${BOLD}HOW TO USE VOICE MODE:${NC}"
    echo ""
    echo -e "  ${BOLD}Start voice conversation:${NC}"
    echo -e "    ${GREEN}claude converse${NC}"
    echo ""
    echo -e "  ${BOLD}Skip permission prompts (trusted environment):${NC}"
    echo -e "    ${GREEN}claude converse --dangerously-skip-permissions${NC}"
    echo ""
    echo -e "  ${BOLD}Or start regular session, then request voice:${NC}"
    echo "    claude"
    echo "    > let's have a voice conversation"
    echo ""
    echo -e "${BLUE}${BOLD}DURING VOICE CONVERSATION:${NC}"
    echo "  • Claude speaks, then listens for your response"
    echo "  • Silence for ~2 seconds ends your turn"
    echo "  • To re-engage voice: type 'listen' or 'let's talk'"
    echo ""
    echo -e "${BLUE}Optimizations (this machine):${NC}"
    echo "  • Whisper: $CPU_CORES threads, base model"
    echo "  • All processing: 100% local (no cloud APIs)"
    echo ""
    echo -e "${BLUE}Upgrade Whisper model:${NC}"
    echo "  • voicemode whisper model set small   (better accuracy)"
    echo "  • voicemode whisper model set medium  (best accuracy)"
else
    echo -e "${YELLOW}${BOLD}              Setup Complete (with warnings)                  ${NC}"
    echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Some services may need attention. Try:"
    echo ""
    echo "  # Restart whisper:"
    echo "  $START_SCRIPT &"
    echo ""
    echo "  # Restart kokoro:"
    echo "  voicemode kokoro start"
    echo ""
    echo "  # Check logs:"
    echo "  journalctl --user -u voicemode-whisper -f"
fi

echo ""
echo -e "${BLUE}Service commands:${NC}"
echo "    voicemode whisper status"
echo "    voicemode kokoro status"
echo ""
echo -e "${BLUE}Systemd service management (services auto-start on login):${NC}"
echo "    systemctl --user status voicemode-whisper"
echo "    systemctl --user status voicemode-kokoro"
echo "    systemctl --user restart voicemode-whisper"
echo "    systemctl --user restart voicemode-kokoro"
echo "    journalctl --user -u voicemode-whisper -f   # View logs"
echo ""

#!/bin/bash
#
# Voice Mode Teardown Script
# Stops voice services and optionally removes autostart
#
# Usage:
#   ./teardown.sh              # Stop services only
#   ./teardown.sh --disable    # Stop services AND remove autostart
#

set -e

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
KOKORO_DIR="$VOICEMODE_DIR/services/kokoro"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

# Parse arguments
DISABLE_AUTOSTART=false
if [[ "$1" == "--disable" || "$1" == "-d" ]]; then
    DISABLE_AUTOSTART=true
fi

# Helper functions
print_ok()    { echo -e "${GREEN}[✓]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
print_err()   { echo -e "${RED}[✗]${NC} $1"; }
print_step()  { echo -e "\n${BLUE}${BOLD}[$1]${NC} $2\n"; }

echo -e "${BLUE}${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              Voice Mode Teardown Script                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

if $DISABLE_AUTOSTART; then
    echo "Mode: Stop services AND disable autostart"
else
    echo "Mode: Stop services only (use --disable to also remove autostart)"
fi
echo ""

# -----------------------------------------------------------------------------
# STEP 1: Stop Whisper Server
# -----------------------------------------------------------------------------
print_step "1/3" "Stopping Whisper server..."

# Try systemd first
if systemctl --user is-active voicemode-whisper &>/dev/null; then
    systemctl --user stop voicemode-whisper 2>/dev/null || true
    print_ok "Stopped Whisper via systemd"
fi

# Kill any remaining whisper processes
if pgrep -f whisper-server &>/dev/null; then
    pkill -f whisper-server 2>/dev/null || true
    sleep 1
    # Force kill if still running
    if pgrep -f whisper-server &>/dev/null; then
        pkill -9 -f whisper-server 2>/dev/null || true
    fi
    print_ok "Stopped Whisper processes"
else
    print_ok "Whisper was not running"
fi

# Verify
if pgrep -f whisper-server &>/dev/null; then
    print_warn "Some Whisper processes may still be running"
else
    print_ok "Whisper fully stopped"
fi

# -----------------------------------------------------------------------------
# STEP 2: Stop Kokoro Server
# -----------------------------------------------------------------------------
print_step "2/3" "Stopping Kokoro server..."

# Try systemd first
if systemctl --user is-active voicemode-kokoro &>/dev/null; then
    systemctl --user stop voicemode-kokoro 2>/dev/null || true
    print_ok "Stopped Kokoro via systemd"
fi

# Kill any remaining kokoro processes
KOKORO_KILLED=false
if pgrep -f "uvicorn.*8880" &>/dev/null; then
    pkill -f "uvicorn.*8880" 2>/dev/null || true
    KOKORO_KILLED=true
fi
if pgrep -f "$KOKORO_DIR" &>/dev/null; then
    pkill -f "$KOKORO_DIR" 2>/dev/null || true
    KOKORO_KILLED=true
fi

if $KOKORO_KILLED; then
    sleep 1
    # Force kill if still running
    pkill -9 -f "uvicorn.*8880" 2>/dev/null || true
    pkill -9 -f "$KOKORO_DIR" 2>/dev/null || true
    print_ok "Stopped Kokoro processes"
else
    print_ok "Kokoro was not running"
fi

# Verify via health endpoint
if curl -s -m 2 http://127.0.0.1:8880/health &>/dev/null; then
    print_warn "Kokoro health endpoint still responding"
else
    print_ok "Kokoro fully stopped"
fi

# -----------------------------------------------------------------------------
# STEP 3: Disable Autostart (optional)
# -----------------------------------------------------------------------------
print_step "3/3" "Managing autostart services..."

if $DISABLE_AUTOSTART; then
    echo "Disabling autostart services..."

    # Disable Whisper service
    if systemctl --user is-enabled voicemode-whisper &>/dev/null; then
        systemctl --user disable voicemode-whisper 2>/dev/null || true
        print_ok "Disabled Whisper autostart"
    else
        print_ok "Whisper autostart was not enabled"
    fi

    # Disable Kokoro service
    if systemctl --user is-enabled voicemode-kokoro &>/dev/null; then
        systemctl --user disable voicemode-kokoro 2>/dev/null || true
        print_ok "Disabled Kokoro autostart"
    else
        print_ok "Kokoro autostart was not enabled"
    fi

    # Reload systemd
    systemctl --user daemon-reload 2>/dev/null || true

    echo ""
    echo -e "${YELLOW}Note:${NC} Service files remain in $SYSTEMD_USER_DIR"
    echo "      Run ./setup.sh to re-enable autostart"
else
    print_ok "Autostart settings unchanged (use --disable to remove)"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}                    Teardown Complete                         ${NC}"
echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${BLUE}Current status:${NC}"
echo -n "  Whisper: "
if pgrep -f whisper-server &>/dev/null; then
    echo -e "${YELLOW}still running${NC}"
else
    echo -e "${GREEN}stopped${NC}"
fi

echo -n "  Kokoro:  "
if curl -s -m 1 http://127.0.0.1:8880/health &>/dev/null; then
    echo -e "${YELLOW}still running${NC}"
else
    echo -e "${GREEN}stopped${NC}"
fi

if $DISABLE_AUTOSTART; then
    echo -n "  Autostart: "
    if systemctl --user is-enabled voicemode-whisper &>/dev/null || \
       systemctl --user is-enabled voicemode-kokoro &>/dev/null; then
        echo -e "${YELLOW}partially enabled${NC}"
    else
        echo -e "${GREEN}disabled${NC}"
    fi
fi

echo ""
echo -e "${BLUE}To restart services:${NC}"
echo "    ./setup.sh"
echo ""
echo -e "${BLUE}Or manually:${NC}"
echo "    voicemode whisper start"
echo "    voicemode kokoro start"
echo ""

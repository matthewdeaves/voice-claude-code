# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository provides local voice mode setup for Claude Code on Linux. It integrates:
- **Whisper.cpp** for local speech-to-text (STT)
- **Kokoro** for local text-to-speech (TTS)

All audio processing happens locally - no cloud APIs or data leaves the machine.

## Repository Structure

```
setup.sh          # Main setup script (idempotent, safe to re-run)
templates/        # Systemd service templates with {{placeholders}}
  voicemode-whisper.service
  voicemode-kokoro.service
```

The setup script installs voice-mode to `~/.voicemode/` with services at:
- Whisper: `~/.voicemode/services/whisper/` (port 2022)
- Kokoro: `~/.voicemode/services/kokoro/` (port 8880)

## Common Commands

### Setup and Installation
```bash
./setup.sh                    # Install/update everything (idempotent)
```

### Service Management
```bash
voicemode whisper status      # Check Whisper service
voicemode kokoro status       # Check Kokoro service
voicemode whisper restart     # Restart Whisper
voicemode kokoro restart      # Restart Kokoro

# Systemd commands (services auto-start on login)
systemctl --user status voicemode-whisper
systemctl --user restart voicemode-whisper
journalctl --user -u voicemode-whisper -f   # View logs
```

### Using Voice Mode
```bash
claude converse               # Start voice conversation
```

## Key Files

- `setup.sh`: 9-step idempotent installer that:
  1. Installs system dependencies via apt
  2. Installs uv package manager
  3. Installs voice-mode via `uvx voice-mode-install`
  4. Configures library paths (`/etc/ld.so.conf.d/voicemode.conf`)
  5. Creates optimized Whisper start script
  6. Configures `~/.voicemode/voicemode.env`
  7. Creates systemd user services from templates
  8. Starts services
  9. Verifies setup

- `templates/*.service`: Systemd unit files with `{{WHISPER_DIR}}`, `{{KOKORO_DIR}}`, etc. placeholders processed by `setup.sh`

## Configuration

Settings in `~/.voicemode/voicemode.env`:
- `VOICEMODE_WHISPER_MODEL`: Model size (tiny/base/small/medium/large)
- `VOICEMODE_WHISPER_THREADS`: CPU threads for Whisper
- `VOICEMODE_SILENCE_THRESHOLD_MS`: Silence duration to end recording
- `VOICEMODE_MIN_RECORDING_DURATION`: Minimum recording time

## External Documentation

Full voice-mode docs: https://voice-mode.readthedocs.io

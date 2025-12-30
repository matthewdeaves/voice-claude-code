# Voice-Enabled Claude Code

Two-way voice conversations with Claude Code, fully local.

## Prerequisites

- **Linux** (Ubuntu/Debian-based recommended)
- **Claude Code CLI** installed and configured
- ~2GB disk space for models
- Working microphone and speakers/headphones

## Quick Start

1. Run the setup script:
   ```bash
   ./setup.sh
   ```

2. In any project folder, start a voice session:
   ```bash
   claude converse
   ```

## How It Works

- **Your voice** -> Whisper.cpp (local) -> text -> Claude Code
- **Claude's response** -> Kokoro (local) -> audio -> your speakers

All processing happens on your machine. No API keys, no cloud, no data leaving your system.

## Using Voice Claude in Your Projects

After setup, you can use voice mode in any project:

```bash
cd ~/my-awesome-app
claude converse
```

Just speak naturally to Claude Code about your project!

## Configuration

Adjust settings in VoiceMode:
- Voice speed/pitch
- Whisper model size (tiny/base/small/medium/large)
- Silence detection sensitivity

Docs: https://voice-mode.readthedocs.io

## Managing Services

Check status:
```bash
voicemode whisper status
voicemode kokoro status
```

Restart services:
```bash
voicemode whisper restart
voicemode kokoro restart
```

## Troubleshooting

- **No mic input:** Check PulseAudio/PipeWire permissions
- **Slow recognition:** Use smaller Whisper model
- **No audio output:** Verify speaker/headphone selection
- **Services not starting:** Run `./setup.sh` again to reinitialize

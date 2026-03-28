# Security Hardening Prompt: voice-claude-code

**Repo:** `/tmp/voice-claude-code`
**Type:** Shell setup script for voice mode with Claude Code
**Default branch:** main
**CI Workflows:** None

---

## 1. Document the curl|bash risk

**File:** `setup.sh` (line 97)

Current:
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

This is the classic pipe-to-shell pattern. While `astral.sh/uv` is a well-known tool from the Astral team (creators of Ruff), piping a remote script directly into `sh` carries inherent risks:

- **No integrity verification** -- if the server is compromised or a MITM attack occurs, arbitrary code runs with the user's privileges.
- **No pinned version** -- the install script can change at any time without notice.
- **Silent execution** -- the `-s` flag in curl suppresses errors, and the user cannot review the script before execution.

**Action:** Add a comment block in `setup.sh` above the curl line:

```bash
# SECURITY NOTE: The following command pipes a remote script directly into sh.
# This is a common but inherently risky pattern (pipe-to-shell). The script is
# fetched from astral.sh, maintained by the Astral team (creators of Ruff/uv).
#
# To verify before running:
#   1. Download first:  curl -LsSf https://astral.sh/uv/install.sh -o /tmp/uv-install.sh
#   2. Review:          less /tmp/uv-install.sh
#   3. Execute:         sh /tmp/uv-install.sh
#
# Alternatively, install uv via your system package manager:
#   - Arch Linux: pacman -S uv
#   - Homebrew:   brew install uv
#   - pipx:       pipx install uv
```

Additionally, consider offering a safer alternative in the script itself:

```bash
if ! command_exists uv; then
    # Download, verify, then execute (safer than direct pipe)
    UV_INSTALLER="/tmp/uv-install-$$.sh"
    curl -LsSf https://astral.sh/uv/install.sh -o "$UV_INSTALLER"
    # Users can review $UV_INSTALLER before this line executes
    sh "$UV_INSTALLER"
    rm -f "$UV_INSTALLER"
    export PATH="$HOME/.local/bin:$PATH"
    print_ok "uv installed"
else
    print_skip "uv ready"
fi
```

**Other security observations in `setup.sh`:**

- **Line 452:** `claude mcp add --scope user voicemode -- uvx --refresh voice-mode` -- this adds an MCP server that runs via `uvx`, which pulls the latest version each time. Consider documenting the trust implications.
- **Lines 164-169:** The script writes to `/etc/ld.so.conf.d/` via `sudo tee`, modifying system-wide library paths. This is necessary but should be clearly documented as requiring root trust.
- **Lines 336-339, 372-378:** The script uses `pkill -9` to forcefully kill processes. While functional, document that this is expected behavior so users are not alarmed.

---

## 2. Add SECURITY.md

**Create file:** `SECURITY.md`

```markdown
# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| Latest  | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly:

1. **Do not** open a public GitHub issue.
2. Use GitHub's private vulnerability reporting feature
   (Security tab > "Report a vulnerability").
3. Include a description of the vulnerability, steps to reproduce, and potential impact.
4. You can expect an initial response within 7 days.

## Security Considerations

This project is a setup script that:

- **Installs system packages** via `apt-get` (requires sudo).
- **Downloads and executes remote scripts** (uv installer from `astral.sh`).
- **Modifies system library paths** (`/etc/ld.so.conf.d/voicemode.conf`).
- **Creates systemd user services** for Whisper and Kokoro.
- **Manages local AI services** (Whisper STT, Kokoro TTS) that listen on localhost ports 2022 and 8880.

### Trust Model

- All AI processing is local (no cloud APIs).
- Whisper and Kokoro services bind to `0.0.0.0` (all interfaces). If running on a machine with a public IP, ensure firewall rules restrict access to ports 2022 and 8880.
- The MCP server integration (`voicemode`) is installed via `uvx`, which fetches the latest version. Review the `voice-mode` package on PyPI for trust assessment.

### Recommendations for Users

1. Review `setup.sh` before running it.
2. Ensure your firewall blocks external access to ports 2022 (Whisper) and 8880 (Kokoro).
3. Regularly update the voice-mode package: `uvx --refresh voice-mode --version`.
```

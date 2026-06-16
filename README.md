# OpenCode Desktop

A cross-platform desktop app (macOS, Linux) that wraps `opencode serve`'s web GUI using the Wizardry framework.

When launched, it starts `opencode serve` in the background, waits for the
server to be ready, then displays the full OpenCode web interface in an
embedded viewport — no browser tab needed.

### Usage

Make sure `opencode` is installed and available in your `PATH`, then run the
app via the Wizardry runtime.

The app uses `opencode serve --port 0` (random available port) by default.

### Controls

| Button | Action |
|--------|--------|
| ↗      | Open the web GUI in your default browser |
| ⟳      | Reload the embedded web GUI |

- **License:** OWL 3.1

### CI Artifacts

GitHub Actions builds desktop artifacts for both target platforms:

- Linux: `OpenCode-x86_64.AppImage`
- macOS: `OpenCode.app` plus `OpenCode-macos.zip`

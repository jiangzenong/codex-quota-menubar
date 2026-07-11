# Codex Quota Menu Bar

[中文](README.md)

A native macOS menu bar app that shows the remaining Codex five-hour and weekly quota in real time.

## Features

- Menu bar display: `5h 72% · W 54%`
- Left-click to refresh and open the detail window
- Right-click menu: refresh now, show/hide details, open Codex Usage, launch at login, and quit
- Detail window with plan, quota progress, reset times, and reset credits when returned by the service
- Draggable, always-on-top detail window

## Build and run

Sign in to Codex Desktop or the Codex CLI before first use.

```bash
./Scripts/build-app.sh
open dist/CodexQuotaMenuBar.app
```

The unsigned local app is created at `dist/CodexQuotaMenuBar.app`. It reads only `~/.codex/auth.json` (or `CODEX_HOME/auth.json`) and sends the existing login token only to Codex quota endpoints on `chatgpt.com`. It does not save tokens, chat content, or raw API responses.

The detail panel supports dynamic colors and floating-orb mode. Official usage analytics render only when the service returns real records; otherwise the app shows an unavailable state and links to the official Usage page.

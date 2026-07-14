<p align="center">
  <img src="Assets/AppIcon.png" width="112" alt="Codex Quota Menu Bar icon">
</p>

<h1 align="center">Codex Quota Menu Bar</h1>

<p align="center">See your live Codex quota, reset times, and recent usage from the macOS menu bar.</p>

<p align="center">
  <a href="https://github.com/jiangzenong/codex-quota-menubar/releases/latest"><img src="https://img.shields.io/github/v/release/jiangzenong/codex-quota-menubar?display_name=tag&style=flat-square" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-black?style=flat-square&logo=apple" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6">
  <a href="README.md">简体中文</a>
</p>

<p align="center">
  <img src="Assets/Screenshots/dashboard.png" width="526" alt="Codex Quota Menu Bar dashboard">
</p>

## Interface Preview

### Menu Bar and Floating Orb

<p align="center">
  <img src="Assets/Screenshots/menu-bar-orb.png" width="215" alt="Codex Quota Menu Bar menu bar and floating orb">
</p>

### Light and Dark Themes

<table>
  <tr>
    <td align="center"><strong>Light theme</strong></td>
    <td align="center"><strong>Dark theme</strong></td>
  </tr>
  <tr>
    <td><img src="Assets/Screenshots/dashboard.png" alt="Codex Quota Menu Bar light theme dashboard"></td>
    <td><img src="Assets/Screenshots/dashboard-dark.png" alt="Codex Quota Menu Bar dark theme dashboard"></td>
  </tr>
</table>

## Highlights

- Displays the quota windows actually returned by the service instead of assuming both 5-hour and 7-day windows are always present.
- Shows the plan, remaining quota, reset time, daily usage, and recent model usage trends in one panel.
- Supports 30-second, 1-minute, 2-minute, and manual refresh modes.
- Lets the detail panel and floating orb remain visible independently; the panel uses a normal window level, while the draggable orb exposes a close control on hover.
- Left-click the menu bar quota to open the quota popover; right-click for the complete action menu.
- Can launch at login and reuses your existing Codex sign-in without asking for another password.

## Download

Download the latest build from [Releases](https://github.com/jiangzenong/codex-quota-menubar/releases/latest). DMG is recommended: open it and drag the app to Applications.

- Apple silicon: `CodexQuotaMenuBar-macos-apple-silicon.dmg`
- Intel: `CodexQuotaMenuBar-macos-intel.dmg`
- ZIP archives are also provided as a fallback.

Current release artifacts are ad-hoc signed and are not notarized with an Apple Developer ID. macOS may ask you to confirm the app in **System Settings → Privacy & Security** the first time it opens.

## Requirements

- macOS 15 or later.
- An existing Codex Desktop or Codex CLI sign-in.
- Network access to `chatgpt.com`.

## Usage

On launch, the app reads your existing local Codex sign-in state and requests quota data. The menu bar reflects the windows currently returned by the service, such as `5h 72% · 7d 54%`; if only one window exists, only that window is shown.

- The floating orb is shown by default at launch. After you close it, automatic refreshes do not show it again during that app run.
- Left-click the menu bar quota to open a compact popover with quota and reset information or a link to full details. It closes when you click elsewhere, switch apps, or press Esc.
- Right-click it to refresh, show or hide the panel, toggle the floating orb, open Codex Usage, manage launch at login, or quit.
- Use the panel header to refresh, change theme or language, independently show or hide the orb, or close the detail panel.
- Click the orb to open or focus the detail panel without hiding the orb; hover over it to reveal its own close button.

## Privacy and security

The app reads the existing access token from `~/.codex/auth.json` (or `CODEX_HOME/auth.json`) and sends requests only to Codex quota and usage endpoints under `https://chatgpt.com/backend-api/wham/...`. It does not persist the access token, chat content, or raw responses, and it adds no separate telemetry.

This is an unofficial open-source utility and is not affiliated with or endorsed by OpenAI. It relies on the web endpoints currently used by Codex, so endpoint changes may temporarily break functionality.

## Build locally

Swift 6 and Xcode Command Line Tools are required:

```bash
swift test
./Scripts/build-app.sh
open dist/CodexQuotaMenuBar.app
```

The app bundle is written to `dist/CodexQuotaMenuBar.app`. The script generates the icon, writes bundle metadata, and applies an ad-hoc signature.

## Troubleshooting

### No quota appears in the menu bar

Confirm that Codex Desktop or the Codex CLI is signed in, then right-click the menu bar quota and choose **Refresh Now**. If no data appears, sign in to Codex again and retry.

### macOS blocks the app from opening

Confirm the installer came from this repository's [Releases](https://github.com/jiangzenong/codex-quota-menubar/releases/latest). In Finder, Control-click the app and choose **Open**, or go to **System Settings → Privacy & Security** and choose **Open Anyway**.

### The app says it is damaged and cannot be opened

Download the release for your architecture again. If you have confirmed it came from this repository but macOS quarantine still blocks it, run:

```bash
xattr -dr com.apple.quarantine /Applications/CodexQuotaMenuBar.app
```

Do not bypass macOS security checks for an app from an unknown source.

### Swift is unavailable

Install Xcode Command Line Tools and retry:

```bash
xcode-select --install
```

## Project status

This project is still at an early stage. Feature feedback and reproducible bug reports are welcome in [Issues](https://github.com/jiangzenong/codex-quota-menubar/issues).

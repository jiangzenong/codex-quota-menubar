# Codex Quota Menu Bar

A native macOS menu bar app for viewing your current Codex five-hour and weekly quota.

## How it works

On launch, the app reads the existing local Codex sign-in state and requests quota data from Codex. It shows the result in the menu bar, for example: `5h 72% · 7d 54%`.

- Left-click the menu bar quota to refresh and open the detail panel.
- Right-click it to refresh, show or hide the panel, use the floating orb, manage launch at login, or quit.
- The detail panel shows the plan, quota progress, and reset time, and can be moved.
- You can collapse the panel into a floating orb and click the orb to expand it again.

The app doesn't ask for a separate username or password. Before first use, sign in to Codex Desktop or the Codex CLI.

## Download

Download the latest version from [Releases](https://github.com/jiangzenong/codex-quota-menubar/releases/latest). Cloning the repository and building locally aren't required. DMG is recommended: open it and drag the app to the Applications folder.

- Apple silicon Macs: `CodexQuotaMenuBar-macos-apple-silicon.dmg`
- Intel Macs: `CodexQuotaMenuBar-macos-intel.dmg`
- ZIP files are also available as a fallback.

## Build and launch

macOS and Swift 6 are required.

```bash
./Scripts/build-app.sh
open dist/CodexQuotaMenuBar.app
```

The built app is `dist/CodexQuotaMenuBar.app`. The build script also generates and embeds the application icon.

## Security and privacy

The app reads only your existing Codex sign-in credentials from `~/.codex/auth.json` (or `CODEX_HOME/auth.json`) and sends that existing token only to Codex quota endpoints on `chatgpt.com`. It doesn't store the token, chat content, or raw API responses.

## Troubleshooting

### No quota appears in the menu bar

Confirm that you are signed in to Codex Desktop or the Codex CLI, then right-click the menu bar quota and choose **Refresh Now**. If no data appears, sign in to Codex again and retry.

### macOS blocks the app from opening

The app is unsigned. In Finder, Control-click the app and choose **Open**, or allow it in **System Settings → Privacy & Security**.

### The DMG or app says it is damaged and can't be opened

If the DMG itself can't be mounted, delete it and download it again from [Releases](https://github.com/jiangzenong/codex-quota-menubar/releases/latest). Don't bypass macOS security checks for a DMG from an unknown source.

If the DMG opens but the app still reports that it is damaged after you drag it to Applications, first confirm that it came from this repository's Release. Then run:

```bash
xattr -dr com.apple.quarantine /Applications/CodexQuotaMenuBar.app
```

Try opening the app again. If macOS still asks for confirmation, go to **System Settings → Privacy & Security** and choose **Open Anyway**.

### Finder still shows the generic app icon

Run `./Scripts/build-app.sh` again and replace the old app with the newly built `dist/CodexQuotaMenuBar.app`. If Finder still shows a cached icon, close and reopen that Finder window.

### Swift isn't available or the build fails

Install Xcode Command Line Tools and try again:

```bash
xcode-select --install
```

# AGENTS.md

This file is the public contributor guide for coding agents working in this repository. Keep private prompts, scratch notes, review transcripts, and implementation plans outside Git; `docs/superpowers/` and common local agent directories are intentionally ignored.

## Project overview

Codex Quota Menu Bar is a native macOS 15+ menu bar app written in Swift 6. It reads the user's existing Codex sign-in state, fetches the quota windows and recent usage analytics returned by Codex, and presents them in a menu bar title, a detail panel, and a compact floating orb.

The project is unofficial and depends on Codex web endpoints that may change without notice.

## Repository layout

- `Sources/QuotaCore/`: authentication loading, quota/analytics requests, parsing, and display formatting.
- `Sources/QuotaMenuBar/`: AppKit lifecycle, menu bar behavior, window management, and SwiftUI dashboard.
- `Tests/QuotaCoreTests/`: parser and formatting tests.
- `Tests/QuotaMenuBarTests/`: menu routing and view-model behavior tests.
- `Scripts/build-app.sh`: release build and `.app` bundle assembly.
- `Assets/`: public application and documentation images.
- `.github/workflows/release.yml`: tag-driven Apple silicon and Intel release packaging.

## Commands

```bash
swift test
swift build
./Scripts/build-app.sh
open dist/CodexQuotaMenuBar.app
```

Before committing, run at least `swift test` and `git diff --check`. Run `./Scripts/build-app.sh` when changing packaging, the icon, bundle metadata, or release behavior.

## Implementation rules

- Make the smallest change that satisfies the request; do not refactor unrelated code.
- Keep `QuotaCore` independent of AppKit and SwiftUI.
- Treat the service response as dynamic. Do not hard-code assumptions that quota always contains both a 5-hour and 7-day window.
- Preserve the current contract: validate percentages, accept seconds or milliseconds for reset timestamps, sort known windows by duration, and show only windows actually returned by the service.
- Keep UI state changes on the main actor and preserve left-click detail / right-click context-menu behavior.
- Add or update focused tests for parser, formatting, routing, or state-management changes.
- Keep Chinese and English UI copy aligned.

## Privacy and security

- Read credentials only from `CODEX_HOME/auth.json` or `~/.codex/auth.json`.
- Send the existing access token only to the required `https://chatgpt.com/backend-api/wham/...` endpoints.
- Never log, persist, commit, or expose access tokens, account identifiers, raw responses, or local authentication files.
- Do not add telemetry or new network destinations without explicit product approval and matching documentation.

## Releases

The release workflow runs for tags matching `v*`, builds Apple silicon and Intel artifacts, and publishes DMG and ZIP files. Release tags must be created from `main`, and published `main` history must not be rewritten so tags cease to be ancestors. `Scripts/build-app.sh` derives its default bundle version from the latest reachable `v*` Git tag; pass `APP_VERSION` explicitly only when an override is required.

This repository currently uses ad-hoc signing and does not claim Developer ID notarization. Keep README installation guidance accurate until signing or distribution changes are actually implemented.

## Public repository hygiene

- Commit only material suitable for an open repository.
- Do not commit `docs/superpowers/`, agent scratch directories, local settings, environment files, logs, credentials, or generated build output.
- Keep public documentation focused on users and contributors. Store internal decision logs and temporary execution plans locally.
- Before staging, inspect both `git status --short` and the complete staged diff.

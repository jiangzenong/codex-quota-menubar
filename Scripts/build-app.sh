#!/bin/zsh
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
swift build -c release
app="$root/dist/CodexQuotaMenuBar.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$root/.build/release/CodexQuotaMenuBar" "$app/Contents/MacOS/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>CodexQuotaMenuBar</string><key>CFBundleIdentifier</key><string>local.codex.quota-menubar</string><key>CFBundleName</key><string>CodexQuotaMenuBar</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
echo "$app"

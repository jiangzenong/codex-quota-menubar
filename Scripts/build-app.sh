#!/bin/zsh
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
app_version=${APP_VERSION:-0.1.6}
build_number=${BUILD_NUMBER:-1}
swift build -c release
app="$root/dist/CodexQuotaMenuBar.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/.build/release/CodexQuotaMenuBar" "$app/Contents/MacOS/"
iconset_root=$(mktemp -d)
iconset="$iconset_root/AppIcon.iconset"
mkdir "$iconset"
trap 'rm -rf "$iconset_root"' EXIT
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$root/Assets/AppIcon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  double_size=$((size * 2))
  sips -z "$double_size" "$double_size" "$root/Assets/AppIcon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>CodexQuotaMenuBar</string><key>CFBundleIconFile</key><string>AppIcon.icns</string><key>CFBundleIconFiles</key><array><string>AppIcon.icns</string></array><key>CFBundleIdentifier</key><string>local.codex.quota-menubar</string><key>CFBundleName</key><string>CodexQuotaMenuBar</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>$app_version</string><key>CFBundleVersion</key><string>$build_number</string></dict></plist>
PLIST
touch "$app"
codesign --force --deep --sign - "$app"
echo "$app"

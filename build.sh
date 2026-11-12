#!/bin/zsh
# Builds QuietMouse.app next to this script.
set -e
cd "$(dirname "$0")"
APP=QuietMouse.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 quietmouse.swift -o "$APP/Contents/MacOS/QuietMouse"
cp Icon/AppIcon.icns Icon/Logo-Light.png Icon/Logo-Dark.png "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.danielye.quietmouse</string>
  <key>CFBundleName</key><string>Quiet Mouse</string>
  <key>CFBundleDisplayName</key><string>Quiet Mouse</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>QuietMouse</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
xattr -cr "$APP"
codesign --force --sign - "$APP"
echo "Built $APP"

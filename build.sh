#!/bin/zsh
# Builds QuietMouse.app next to this script (universal, macOS 13+).
set -e
cd "$(dirname "$0")"
APP=QuietMouse.app
MIN_OS=13.0
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

swiftc -O -swift-version 5 -target "arm64-apple-macos${MIN_OS}" quietmouse.swift -o "$workdir/QuietMouse-arm64"
if swiftc -O -swift-version 5 -target "x86_64-apple-macos${MIN_OS}" quietmouse.swift -o "$workdir/QuietMouse-x86_64"; then
  lipo -create -output "$APP/Contents/MacOS/QuietMouse" "$workdir/QuietMouse-arm64" "$workdir/QuietMouse-x86_64"
  echo "Built universal binary (arm64 + x86_64), macOS ${MIN_OS}+"
else
  echo "x86_64 build failed; shipping arm64 only" >&2
  cp "$workdir/QuietMouse-arm64" "$APP/Contents/MacOS/QuietMouse"
fi

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
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>${MIN_OS}</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Copyright 2026 Ye Zicheng. Apache License 2.0.</string>
</dict></plist>
PLIST
xattr -cr "$APP"
codesign --force --sign - "$APP"
echo "Built $APP"

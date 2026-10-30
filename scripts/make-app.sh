#!/bin/bash
# Builds TokenCoach.app (a real app bundle, needed for Mac notifications) into .build/.
# --universal builds one app that runs on both Apple Silicon and Intel Macs (for sharing).
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" = "--universal" ]; then
    swift build -c release --product TokenCoach --arch arm64 --arch x86_64
    bin=.build/out/Products/Release/TokenCoach
else
    swift build -c release --product TokenCoach
    bin=.build/release/TokenCoach
fi
app=.build/TokenCoach.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/TokenCoach"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.tokencoach.app</string>
    <key>CFBundleName</key><string>TokenCoach</string>
    <key>CFBundleExecutable</key><string>TokenCoach</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$app"
echo "Built $app  (open it with: open $app)"

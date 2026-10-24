#!/bin/sh
# Builds "Spoof by Ziz.app" and installs it to /Applications (or ~/Applications).
# Needs Xcode's command line tools and `pipx install pymobiledevice3`.
set -e
cd "$(dirname "$0")"
APP="build/Spoof by Ziz.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset

swiftc -O main.swift -o "$APP/Contents/MacOS/SpoofByZiz" -framework Cocoa -framework WebKit
cp ../spoof.py ../ui.html "$APP/Contents/Resources/"

swift make_icon.swift build/icon.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Spoof by Ziz</string>
  <key>CFBundleDisplayName</key><string>Spoof by Ziz</string>
  <key>CFBundleIdentifier</key><string>com.ziz.spoof</string>
  <key>CFBundleExecutable</key><string>SpoofByZiz</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>BY ZIZ</string>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
EOF

codesign --force --deep -s - "$APP"

DEST=/Applications
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
rm -rf "$DEST/Spoof by Ziz.app"
cp -R "$APP" "$DEST/"
echo "Installed: $DEST/Spoof by Ziz.app"

#!/bin/bash

set -e

# Simple logger
log() { echo "[DisplayWatcher Build] $1"; }

# Check Swift source presence
if [ ! -f "DisplayWatcher.swift" ]; then
  echo "[Error] DisplayWatcher.swift not found in current directory."
  exit 1
fi

# Build Swift binary
log "Building Swift binary..."
swiftc -framework IOKit -o DisplayWatcher DisplayWatcher.swift

# Create macOS app bundle structure
log "Creating app bundle..."
APP_DIR="DisplayWatcher.app/Contents"
mkdir -p "$APP_DIR/MacOS"
cp DisplayWatcher "$APP_DIR/MacOS"

# Generate iconset and icns
log "Generating iconset..."
ICONSET_DIR="DisplayWatcher.iconset"
rm -rf "$ICONSET_DIR"
mkdir "$ICONSET_DIR"

sips -z 16 16     DisplayWatcher.png --out "$ICONSET_DIR/icon_16x16.png"
sips -z 32 32     DisplayWatcher.png --out "$ICONSET_DIR/icon_16x16@2x.png"
sips -z 32 32     DisplayWatcher.png --out "$ICONSET_DIR/icon_32x32.png"
sips -z 64 64     DisplayWatcher.png --out "$ICONSET_DIR/icon_32x32@2x.png"
sips -z 128 128   DisplayWatcher.png --out "$ICONSET_DIR/icon_128x128.png"
sips -z 256 256   DisplayWatcher.png --out "$ICONSET_DIR/icon_128x128@2x.png"
sips -z 256 256   DisplayWatcher.png --out "$ICONSET_DIR/icon_256x256.png"
sips -z 512 512   DisplayWatcher.png --out "$ICONSET_DIR/icon_256x256@2x.png"
sips -z 512 512   DisplayWatcher.png --out "$ICONSET_DIR/icon_512x512.png"
cp DisplayWatcher.png "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR"
mkdir -p "$APP_DIR/Resources"
mv DisplayWatcher.icns "$APP_DIR/Resources"

# Write Info.plist
log "Writing Info.plist..."
cat > "$APP_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>DisplayWatcher</string>
    <key>CFBundleIdentifier</key>
    <string>com.user.displaywatcher</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>DisplayWatcher</string>
    <key>CFBundleIconFile</key>
    <string>DisplayWatcher</string>
</dict>
</plist>
PLIST

log "✅ Build complete!"


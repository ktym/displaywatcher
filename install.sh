#!/bin/bash

set -e

# Simple logger
log() { echo "[DisplayWatcher Installer] $1"; }

# Install app bundle to /Applications
log "Installing app bundle..."
if [ ! -d "DisplayWatcher.app" ]; then
  echo "[Error] DisplayWatcher.app not found. Please run build.sh first."
  exit 1
fi

sudo rm -rf "/Applications/DisplayWatcher.app"
sudo cp -R "DisplayWatcher.app" /Applications/

# Create config directory
log "Creating config directory..."
CONFIG_DIR="$HOME/Library/Application Support/DisplayWatcher"
mkdir -p "$CONFIG_DIR"

# Create config file template if not exists
CONFIG_FILE="$CONFIG_DIR/displaywatcher.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  log "Writing config template..."
  cat > "$CONFIG_FILE" <<CONF
# DisplayWatcher Configuration
# Specify your preferred built-in display resolution below in the format WIDTHxHEIGHT (e.g., 2560x1600)
# Only the first valid line will be used. Lines starting with # or blank lines are ignored.

2560x1600

# Example:
# 1920x1200
CONF
fi

# Register login item automatically
log "Registering login item..."
osascript <<OSA
tell application "System Events"
    if not (exists login item "DisplayWatcher") then
        make login item at end with properties {path:"/Applications/DisplayWatcher.app", hidden:true}
    end if
end tell
OSA

log "✅ Installation complete!"
echo ""
echo "You may now reboot or log out / log in to activate DisplayWatcher automatically."


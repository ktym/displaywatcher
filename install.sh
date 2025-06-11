#!/bin/bash

set -e

# Simple logger
log() { echo "[DisplayWatcher Installer] $1"; }

# Check for Homebrew
if ! command -v brew &>/dev/null; then
    echo "[Error] Homebrew is not installed. Please install Homebrew first: https://brew.sh/"
    exit 1
fi

# Install displayplacer if not installed
if ! command -v displayplacer &>/dev/null; then
    log "Installing displayplacer via Homebrew..."
    brew install displayplacer
else
    log "displayplacer already installed."
fi

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

  DETECTED_COMMAND=$(displayplacer list | grep '^displayplacer "id:' | head -n 1)
  
  cat > "$CONFIG_FILE" <<CONF
# DisplayWatcher Configuration
# Automatically detected current displayplacer configuration:

$DETECTED_COMMAND

# You may modify this if needed.
# Tip:
# - Set your desired display arrangement manually first.
# - Then run: displayplacer list | grep '^displayplacer "id:'
# - Copy the output here to update this configuration.
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


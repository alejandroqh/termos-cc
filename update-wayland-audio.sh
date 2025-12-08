#!/bin/sh
# Update TermOS Wayland session files to add audio toggle support
# Run this script to patch all wayland session files

set -e

echo "This script will update the Wayland session files to add audio enable/disable support."
echo "You will be prompted for your sudo password."
echo ""

# Check if running as root
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
    # Prompt for sudo password upfront
    $SUDO -v || { echo "Failed to obtain sudo privileges"; exit 1; }
fi

# Audio config block to insert
AUDIO_BLOCK='# Start audio subsystem if enabled (check config file)
AUDIO_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/termos/audio_enabled"
if [ ! -f "$AUDIO_CONFIG" ] || [ "$(cat "$AUDIO_CONFIG" 2>/dev/null)" != "disabled" ]; then
    pipewire >/dev/null 2>&1 \&
    sleep 0.2
    pipewire-pulse >/dev/null 2>&1 \&
    wireplumber >/dev/null 2>&1 \&
fi'

# Function to backup and update a file
update_file() {
    local file="$1"
    local has_pipewire="$2"

    if [ ! -f "$file" ]; then
        echo "Warning: $file not found, skipping"
        return
    fi

    echo "Updating $file..."

    # Create backup
    $SUDO cp "$file" "${file}.bak"

    # Create temp file
    local tmpfile=$(mktemp)

    if [ "$has_pipewire" = "yes" ]; then
        # Replace existing pipewire block with conditional version
        $SUDO cat "$file" | awk '
        /^# Start audio subsystem.*check config file/ { skip=1; next }
        /^pipewire >\/dev\/null/ && !skip {
            print "# Start audio subsystem if enabled (check config file)"
            print "AUDIO_CONFIG=\"${XDG_CONFIG_HOME:-$HOME/.config}/termos/audio_enabled\""
            print "if [ ! -f \"$AUDIO_CONFIG\" ] || [ \"$(cat \"$AUDIO_CONFIG\" 2>/dev/null)\" != \"disabled\" ]; then"
            print "    pipewire >/dev/null 2>&1 &"
            next
        }
        /^sleep 0\.2$/ && !already_in_block {
            print "    sleep 0.2"
            next
        }
        /^pipewire-pulse >\/dev\/null/ {
            print "    pipewire-pulse >/dev/null 2>&1 &"
            next
        }
        /^wireplumber >\/dev\/null/ {
            print "    wireplumber >/dev/null 2>&1 &"
            print "fi"
            next
        }
        { print }
        ' > "$tmpfile"
    else
        # Add pipewire block before cage command
        $SUDO cat "$file" | awk '
        /^cage --/ {
            print "# Start audio subsystem if enabled (check config file)"
            print "AUDIO_CONFIG=\"${XDG_CONFIG_HOME:-$HOME/.config}/termos/audio_enabled\""
            print "if [ ! -f \"$AUDIO_CONFIG\" ] || [ \"$(cat \"$AUDIO_CONFIG\" 2>/dev/null)\" != \"disabled\" ]; then"
            print "    pipewire >/dev/null 2>&1 &"
            print "    sleep 0.2"
            print "    pipewire-pulse >/dev/null 2>&1 &"
            print "    wireplumber >/dev/null 2>&1 &"
            print "fi"
            print ""
        }
        { print }
        ' > "$tmpfile"
    fi

    # Copy temp file to destination
    $SUDO cp "$tmpfile" "$file"
    $SUDO chmod 755 "$file"
    rm -f "$tmpfile"

    echo "  Done (backup at ${file}.bak)"
}

echo ""
echo "Updating wayland session files..."
echo ""

# Files with existing pipewire commands
update_file "/usr/bin/termos-wayland-session" "yes"
update_file "/usr/bin/termos-wayland-session-vm" "yes"
update_file "/usr/bin/termos-wayland-retro" "yes"

# Files without pipewire commands (need to add them)
update_file "/usr/bin/termos-wayland-alacritty" "no"
update_file "/usr/bin/termos-wayland-simple" "no"

echo ""
echo "All files updated successfully!"
echo ""
echo "To disable audio, create the config file:"
echo "  mkdir -p ~/.config/termos"
echo "  echo 'disabled' > ~/.config/termos/audio_enabled"
echo ""
echo "To enable audio (default), either delete the file or set it to 'enabled':"
echo "  echo 'enabled' > ~/.config/termos/audio_enabled"
echo "  # or: rm ~/.config/termos/audio_enabled"
echo ""

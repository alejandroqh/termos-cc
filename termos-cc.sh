#!/bin/bash
# TermOS Control Center v2.0
# Hardware settings control panel using dialog

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

# Source common utilities
source "$MODULES_DIR/common.sh"

show_main_menu() {
    while true; do
        choice=$(dialog --clear --backtitle "TermOS Control Center" \
            --title "[ TermOS Control Center ]" \
            --menu "Select a category:" 20 55 12 \
            D "Dashboard" \
            1 "WiFi Settings" \
            2 "Network & VPN" \
            3 "Audio Settings" \
            4 "Display & Brightness" \
            5 "Bluetooth" \
            6 "Storage & Mounts" \
            7 "System Updates" \
            8 "System Info" \
            9 "Power Options" \
            H "Help & About" \
            Q "Exit" \
            2>&1 >/dev/tty)

        exit_status=$?

        # Handle ESC or Cancel
        if [ $exit_status -ne 0 ]; then
            clear
            exit 0
        fi

        case $choice in
            D) source "$MODULES_DIR/dashboard.sh" ;;
            1) source "$MODULES_DIR/wifi.sh" ;;
            2) source "$MODULES_DIR/network.sh" ;;
            3) source "$MODULES_DIR/audio.sh" ;;
            4) source "$MODULES_DIR/display.sh" ;;
            5) source "$MODULES_DIR/bluetooth.sh" ;;
            6) source "$MODULES_DIR/storage.sh" ;;
            7) source "$MODULES_DIR/updates.sh" ;;
            8) source "$MODULES_DIR/sysinfo.sh" ;;
            9) source "$MODULES_DIR/power.sh" ;;
            H) source "$MODULES_DIR/help.sh" ;;
            Q) clear; exit 0 ;;
        esac
    done
}

# Check for dialog
if ! command -v dialog &> /dev/null; then
    echo "Error: dialog is not installed"
    echo "Install with: sudo apk add dialog"
    exit 1
fi

# Check for required modules directory
if [ ! -d "$MODULES_DIR" ]; then
    echo "Error: modules directory not found at $MODULES_DIR"
    exit 1
fi

# Check for common.sh
if [ ! -f "$MODULES_DIR/common.sh" ]; then
    echo "Error: common.sh not found"
    exit 1
fi

show_main_menu

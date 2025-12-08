# Help System Module
# Context-sensitive help and documentation

source "$MODULES_DIR/common.sh"

HELP_DIR="$SCRIPT_DIR/help"

# ============================================================================
# Help Functions
# ============================================================================

show_help() {
    local context="${1:-main}"
    local help_file="$HELP_DIR/${context}.txt"

    if [ -f "$help_file" ]; then
        dialog --backtitle "$BACKTITLE" \
            --title "[ Help: $context ]" \
            --textbox "$help_file" 20 70
    else
        dialog --backtitle "$BACKTITLE" \
            --title "[ Help ]" \
            --msgbox "No help available for: $context\n\nHelp file not found at:\n$help_file" 10 50
    fi
}

show_keybindings() {
    local keys="KEYBOARD SHORTCUTS

Navigation:
  Arrow Keys     Move selection up/down
  Enter          Select highlighted option
  Tab            Move between buttons
  Space          Toggle checkbox/select

Dialog Controls:
  ESC            Go back / Cancel
  Page Up/Down   Scroll in long lists
  Home/End       Jump to start/end

In Menus:
  Type number    Quick select by number
  First letter   Jump to matching item

In Text Entry:
  Ctrl+U         Clear input
  Ctrl+K         Delete to end of line
  Backspace      Delete character"

    dialog --backtitle "$BACKTITLE" \
        --title "[ Keyboard Shortcuts ]" \
        --msgbox "$keys" 22 55
}

show_about() {
    local version="2.0.0"
    local about="TermOS Control Center
Version: $version

A TUI-based system settings manager for
TermOS (Alpine Linux).

Features:
  - Dashboard with system status
  - WiFi & Network management
  - Audio control with per-app volume
  - Display settings & night mode
  - Bluetooth device management
  - Storage & USB management
  - System updates (apk)
  - System monitoring & sensors

Built with:
  - Bash scripting
  - dialog (ncurses)

Project: TermOS Control Center
License: MIT"

    dialog --backtitle "$BACKTITLE" \
        --title "[ About ]" \
        --msgbox "$about" 24 50
}

show_dependencies() {
    local deps="DEPENDENCIES STATUS

Checking installed tools..."

    dialog --backtitle "$BACKTITLE" \
        --infobox "$deps" 5 40

    # Check each tool
    local status=""

    # Core
    status="$status\n=== Core ===\n"
    has_tool dialog && status="$status  dialog: OK\n" || status="$status  dialog: MISSING\n"

    # Audio
    status="$status\n=== Audio ===\n"
    has_tool pactl && status="$status  pactl: OK\n" || status="$status  pactl: Missing\n"
    has_tool pulsemixer && status="$status  pulsemixer: OK\n" || status="$status  pulsemixer: Optional\n"

    # Display
    status="$status\n=== Display ===\n"
    has_tool xrandr && status="$status  xrandr: OK\n" || status="$status  xrandr: Missing (X11)\n"
    has_tool wlr-randr && status="$status  wlr-randr: OK\n" || status="$status  wlr-randr: Missing (Wayland)\n"
    has_tool brightnessctl && status="$status  brightnessctl: OK\n" || status="$status  brightnessctl: Missing\n"
    has_tool redshift && status="$status  redshift: OK\n" || status="$status  redshift: Optional\n"

    # Network
    status="$status\n=== Network ===\n"
    has_tool nmcli && status="$status  nmcli: OK\n" || status="$status  nmcli: Missing\n"
    has_tool wg && status="$status  wg: OK\n" || status="$status  wg: Optional\n"

    # Bluetooth
    status="$status\n=== Bluetooth ===\n"
    has_tool bluetoothctl && status="$status  bluetoothctl: OK\n" || status="$status  bluetoothctl: Missing\n"

    # Storage
    status="$status\n=== Storage ===\n"
    has_tool lsblk && status="$status  lsblk: OK\n" || status="$status  lsblk: Missing\n"
    has_tool udisksctl && status="$status  udisksctl: OK\n" || status="$status  udisksctl: Optional\n"
    has_tool smartctl && status="$status  smartctl: OK\n" || status="$status  smartctl: Optional\n"

    # System
    status="$status\n=== System ===\n"
    has_tool apk && status="$status  apk: OK\n" || status="$status  apk: Missing\n"
    has_tool sensors && status="$status  sensors: OK\n" || status="$status  sensors: Optional\n"

    dialog --backtitle "$BACKTITLE" \
        --title "[ Dependencies ]" \
        --msgbox "$status" 28 45
}

# ============================================================================
# Main Help Menu
# ============================================================================

help_menu() {
    while true; do
        choice=$(dialog --backtitle "$BACKTITLE" \
            --title "[ Help & About ]" \
            --menu "Select topic:" 18 55 9 \
            1 "Main Menu Help" \
            2 "Dashboard" \
            3 "Network & WiFi" \
            4 "Audio" \
            5 "Display & Brightness" \
            6 "Bluetooth" \
            7 "Keyboard Shortcuts" \
            8 "Check Dependencies" \
            9 "About" \
            2>&1 >/dev/tty)

        local exit_status=$?
        [ $exit_status -ne 0 ] && return

        case $choice in
            1) show_help "main" ;;
            2) show_help "dashboard" ;;
            3) show_help "network" ;;
            4) show_help "audio" ;;
            5) show_help "display" ;;
            6) show_help "bluetooth" ;;
            7) show_keybindings ;;
            8) show_dependencies ;;
            9) show_about ;;
        esac
    done
}

help_menu

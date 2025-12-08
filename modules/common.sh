# Common Utilities Library
# Shared functions for all TermOS Control Center modules

BACKTITLE="TermOS Control Center"

# ============================================================================
# Display Server Detection
# ============================================================================

detect_display_server() {
    if [ -n "$WAYLAND_DISPLAY" ]; then
        echo "wayland"
    elif [ -n "$DISPLAY" ]; then
        echo "x11"
    else
        echo "none"
    fi
}

get_randr_cmd() {
    case $(detect_display_server) in
        wayland) echo "wlr-randr" ;;
        x11)     echo "xrandr" ;;
        *)       echo "" ;;
    esac
}

# ============================================================================
# Tool Availability
# ============================================================================

require_tool() {
    local tool="$1"
    local friendly_name="${2:-$tool}"
    if ! command -v "$tool" &>/dev/null; then
        dialog --backtitle "$BACKTITLE" \
            --title "[ Missing Dependency ]" \
            --msgbox "$friendly_name is not installed.\n\nPlease install it with:\n  sudo apk add $tool" 10 50
        return 1
    fi
    return 0
}

has_tool() {
    command -v "$1" &>/dev/null
}

# ============================================================================
# Progress Bar
# ============================================================================

make_bar() {
    local percent=$1
    local width=${2:-30}
    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    printf "[%s%s] %d%%" \
        "$(printf '#%.0s' $(seq 1 $filled 2>/dev/null))" \
        "$(printf '.%.0s' $(seq 1 $empty 2>/dev/null))" \
        "$percent"
}

# ============================================================================
# Notifications
# ============================================================================

notify() {
    local msg="$1"
    local title="${2:-TermOS}"
    if has_tool notify-send; then
        notify-send "$title" "$msg"
    else
        dialog --backtitle "$BACKTITLE" \
            --title "[ $title ]" \
            --infobox "$msg" 5 50
        sleep 1
    fi
}

show_info() {
    local msg="$1"
    local title="${2:-Info}"
    dialog --backtitle "$BACKTITLE" \
        --title "[ $title ]" \
        --infobox "$msg" 5 50
    sleep 1
}

show_message() {
    local msg="$1"
    local title="${2:-Message}"
    dialog --backtitle "$BACKTITLE" \
        --title "[ $title ]" \
        --msgbox "$msg" 10 50
}

# ============================================================================
# Confirmation Dialogs
# ============================================================================

confirm() {
    local msg="$1"
    local title="${2:-Confirm}"
    dialog --backtitle "$BACKTITLE" \
        --title "[ $title ]" \
        --yesno "$msg" 7 50
    return $?
}

# ============================================================================
# Sudo Operations
# ============================================================================

show_sudo_command() {
    local cmd="$1"
    local description="${2:-This operation}"
    dialog --backtitle "$BACKTITLE" \
        --title "[ Requires sudo ]" \
        --msgbox "$description requires root privileges.\n\nPlease run manually:\n\n  sudo $cmd" 12 60
}

# ============================================================================
# Input Dialogs
# ============================================================================

get_input() {
    local prompt="$1"
    local title="${2:-Input}"
    local default="${3:-}"
    dialog --backtitle "$BACKTITLE" \
        --title "[ $title ]" \
        --inputbox "$prompt" 8 50 "$default" 2>&1 >/dev/tty
}

# ============================================================================
# Menu Helpers
# ============================================================================

# Build a menu dynamically from lines of text
# Usage: choice=$(build_menu "title" "prompt" "line1\nline2\nline3")
build_menu() {
    local title="$1"
    local prompt="$2"
    local items="$3"

    local menu_items=""
    local i=1
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        menu_items="$menu_items $i \"$line\" "
        i=$((i + 1))
    done <<< "$items"

    [ -z "$menu_items" ] && return 1

    eval "dialog --backtitle '$BACKTITLE' \
        --title '[ $title ]' \
        --menu '$prompt' 15 60 8 $menu_items" 2>&1 >/dev/tty
}

# ============================================================================
# Status Formatting
# ============================================================================

format_status() {
    local status="$1"
    case "$status" in
        on|yes|true|connected|enabled|active)
            echo "ON"
            ;;
        off|no|false|disconnected|disabled|inactive)
            echo "OFF"
            ;;
        *)
            echo "$status"
            ;;
    esac
}

format_percent() {
    local value="$1"
    echo "${value}%"
}

# ============================================================================
# System Info Helpers
# ============================================================================

get_battery_info() {
    local cap=""
    local status=""
    local bat_path=""

    for path in /sys/class/power_supply/BAT0 /sys/class/power_supply/BAT1; do
        if [ -f "$path/capacity" ]; then
            bat_path="$path"
            break
        fi
    done

    if [ -n "$bat_path" ]; then
        cap=$(cat "$bat_path/capacity" 2>/dev/null)
        status=$(cat "$bat_path/status" 2>/dev/null)
        echo "${cap}% ($status)"
    else
        echo "N/A"
    fi
}

get_memory_percent() {
    free | awk '/^Mem:/ {printf "%.0f", $3/$2*100}'
}

get_disk_percent() {
    # Find the column with % sign (varies by system)
    df / | tail -1 | grep -oE '[0-9]+%' | head -1 | tr -d '%'
}

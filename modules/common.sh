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

# Enhanced battery functions
get_battery_percent() {
    local bat_path=""
    for path in /sys/class/power_supply/BAT0 /sys/class/power_supply/BAT1; do
        if [ -f "$path/capacity" ]; then
            cat "$path/capacity" 2>/dev/null
            return
        fi
    done
    echo "0"
}

get_battery_status() {
    local bat_path=""
    for path in /sys/class/power_supply/BAT0 /sys/class/power_supply/BAT1; do
        if [ -f "$path/status" ]; then
            cat "$path/status" 2>/dev/null
            return
        fi
    done
    echo "Unknown"
}

# Human-readable system info
get_memory_info() {
    free -h 2>/dev/null | awk '/^Mem:/ {printf "%s / %s", $3, $2}'
}

get_disk_info() {
    df -h / 2>/dev/null | tail -1 | awk '{printf "%s / %s", $3, $2}'
}

# ============================================================================
# Dynamic Menu Building
# ============================================================================

# Build a dynamic menu from delimited data and return selected value
# Usage:
#   data="key1:Display 1\nkey2:Display 2"
#   selected=$(build_dynamic_menu "Title" "Prompt" "$data" ":")
#
# Args:
#   $1 - title
#   $2 - prompt
#   $3 - data (multi-line, delimiter-separated)
#   $4 - delimiter (default: ":")
#   $5 - menu height (default: 15)
#   $6 - menu width (default: 60)
#
# Returns: The KEY portion of selected line (first field before delimiter)
build_dynamic_menu() {
    local title="$1"
    local prompt="$2"
    local data="$3"
    local delim="${4:-:}"
    local height="${5:-15}"
    local width="${6:-60}"

    local menu_items=""
    local i=1

    while IFS="$delim" read -r key display_text; do
        [ -z "$key" ] && continue
        menu_items="$menu_items $i \"$display_text\" "
        eval "_menu_item_$i=\"$key\""
        i=$((i + 1))
    done <<< "$data"

    [ -z "$menu_items" ] && return 1

    local choice
    choice=$(eval "dialog --backtitle '$BACKTITLE' \
        --title '[ $title ]' \
        --menu '$prompt' $height $width $((i-2)) $menu_items" 2>&1 >/dev/tty)

    local exit_status=$?
    [ $exit_status -ne 0 ] && return $exit_status

    eval "echo \$_menu_item_$choice"

    # Cleanup
    for ((j=1; j<i; j++)); do
        unset "_menu_item_$j"
    done

    return 0
}

# Simplified version for single-field data (just numbered list)
# Usage:
#   data="Item 1\nItem 2\nItem 3"
#   selected_index=$(build_simple_menu "Title" "Prompt" "$data")
build_simple_menu() {
    local title="$1"
    local prompt="$2"
    local data="$3"
    local height="${4:-15}"
    local width="${5:-60}"

    local menu_items=""
    local i=1

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        menu_items="$menu_items $i \"$line\" "
        i=$((i + 1))
    done <<< "$data"

    [ -z "$menu_items" ] && return 1

    dialog --backtitle "$BACKTITLE" \
        --title "[ $title ]" \
        --menu "$prompt" $height $width $((i-2)) $menu_items 2>&1 >/dev/tty
}

# ============================================================================
# Brightness Control
# ============================================================================

get_brightness() {
    if has_tool brightnessctl; then
        brightnessctl -m 2>/dev/null | cut -d',' -f4 | tr -d '%'
    else
        echo "N/A"
    fi
}

set_brightness() {
    local value="$1"
    if has_tool brightnessctl; then
        brightnessctl set "$value" > /dev/null 2>&1
        return $?
    fi
    return 1
}

brightness_submenu() {
    while true; do
        local current=$(get_brightness)

        if [ "$current" = "N/A" ]; then
            show_message "brightnessctl not available.\n\nInstall with:\n  sudo apk add brightnessctl" "Error"
            return
        fi

        choice=$(dialog --backtitle "$BACKTITLE" \
            --title "[ Brightness ]" \
            --menu "Current: ${current}%" 16 50 6 \
            1 "Increase (+10%)" \
            2 "Decrease (-10%)" \
            3 "Set to 25%" \
            4 "Set to 50%" \
            5 "Set to 75%" \
            6 "Set to 100%" \
            2>&1 >/dev/tty)

        local exit_status=$?
        [ $exit_status -ne 0 ] && return

        case $choice in
            1) set_brightness +10% ;;
            2) set_brightness 10%- ;;
            3) set_brightness 25% ;;
            4) set_brightness 50% ;;
            5) set_brightness 75% ;;
            6) set_brightness 100% ;;
        esac
    done
}

# ============================================================================
# Service & Process Management
# ============================================================================

# Check if a process is running by name
is_process_running() {
    local process_name="$1"
    pgrep -x "$process_name" >/dev/null 2>&1
}

# Get process status (Running/Stopped)
get_process_status() {
    local process_name="$1"
    if is_process_running "$process_name"; then
        echo "Running"
    else
        echo "Stopped"
    fi
}

# Check if service is enabled in a config (generic)
is_service_enabled_in_config() {
    local config_file="$1"
    local disabled_marker="${2:-disabled}"

    if [ ! -f "$config_file" ] || [ "$(cat "$config_file" 2>/dev/null)" != "$disabled_marker" ]; then
        return 0  # Enabled by default if config doesn't exist or doesn't say disabled
    fi
    return 1
}

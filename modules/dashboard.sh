# Dashboard Module - System Status Overview
# Quick-glance view of all system metrics with visual indicators

source "$MODULES_DIR/common.sh"

# ============================================================================
# Visual Indicators & Symbols
# ============================================================================

# Status symbols
SYM_OK="●"
SYM_WARN="●"
SYM_OFF="○"
SYM_ERR="✗"

SYM_WIFI="󰤨"
SYM_WIFI_OFF="󰤭"
SYM_BT="󰂯"
SYM_BT_OFF="󰂲"
SYM_VOL="󰕾"
SYM_VOL_MUTE="󰖁"
SYM_BRIGHT="󰃟"
SYM_BAT="󰁹"
SYM_BAT_CHRG="󰂄"
SYM_CPU="󰻠"
SYM_MEM="󰍛"
SYM_DISK="󰋊"
SYM_TIME="󰥔"

# Fallback to ASCII if nerd fonts not available
use_nerd_fonts() {
    # Check if terminal likely supports nerd fonts
    # For now, use ASCII fallbacks for better compatibility
    return 1
}

if ! use_nerd_fonts; then
    SYM_WIFI="W"
    SYM_WIFI_OFF="W"
    SYM_BT="B"
    SYM_BT_OFF="B"
    SYM_VOL="♪"
    SYM_VOL_MUTE="♪"
    SYM_BRIGHT="*"
    SYM_BAT="▮"
    SYM_BAT_CHRG="▮"
    SYM_CPU="C"
    SYM_MEM="M"
    SYM_DISK="D"
    SYM_TIME="T"
fi

# ============================================================================
# Status Gathering Functions
# ============================================================================

dash_get_wifi() {
    # Try nmcli first
    if has_tool nmcli; then
        local active=$(nmcli -t -f active,ssid,signal dev wifi 2>/dev/null | grep "^yes:" | head -1)
        if [ -n "$active" ]; then
            local ssid=$(echo "$active" | cut -d':' -f2)
            local signal=$(echo "$active" | cut -d':' -f3)
            echo "$SYM_OK|$ssid|${signal}%"
            return
        else
            local wifi_state=$(nmcli radio wifi 2>/dev/null)
            if [ "$wifi_state" = "enabled" ]; then
                echo "$SYM_WARN|Disconnected|No network"
            else
                echo "$SYM_OFF|Disabled|Radio off"
            fi
            return
        fi
    fi

    # Fallback: check via iw/iwconfig or /sys
    local wifi_iface=""
    for iface in /sys/class/net/wlan* /sys/class/net/wlp*; do
        [ -e "$iface" ] && wifi_iface=$(basename "$iface") && break
    done

    if [ -z "$wifi_iface" ]; then
        echo "$SYM_OFF|N/A|No WiFi adapter"
        return
    fi

    # Check if interface is up
    local state=$(cat /sys/class/net/$wifi_iface/operstate 2>/dev/null)
    if [ "$state" = "up" ]; then
        # Try to get SSID via iw or iwgetid
        local ssid=""
        if has_tool iwgetid; then
            ssid=$(iwgetid -r 2>/dev/null)
        elif has_tool iw; then
            ssid=$(iw dev $wifi_iface link 2>/dev/null | grep "SSID:" | cut -d' ' -f2-)
        fi

        # Try to get signal strength
        local signal=""
        if has_tool iw; then
            signal=$(iw dev $wifi_iface link 2>/dev/null | grep "signal:" | awk '{print $2}')
            [ -n "$signal" ] && signal="${signal}dBm"
        fi

        if [ -n "$ssid" ]; then
            echo "$SYM_OK|$ssid|${signal:-Connected}"
        else
            echo "$SYM_OK|Connected|$wifi_iface"
        fi
    else
        echo "$SYM_WARN|Disconnected|$wifi_iface down"
    fi
}

dash_get_bluetooth() {
    if ! has_tool bluetoothctl; then
        echo "$SYM_ERR|N/A|not found"
        return
    fi

    local power=$(bluetoothctl show 2>/dev/null | grep "Powered:" | awk '{print $2}')
    if [ "$power" != "yes" ]; then
        echo "$SYM_OFF|OFF|Radio disabled"
        return
    fi

    local connected=$(bluetoothctl devices Connected 2>/dev/null | head -1 | cut -d' ' -f3-)
    if [ -n "$connected" ]; then
        echo "$SYM_OK|$connected|Connected"
    else
        echo "$SYM_WARN|ON|No devices"
    fi
}

dash_get_volume() {
    if ! has_tool pactl; then
        echo "$SYM_ERR|N/A|pactl not found"
        return
    fi

    local vol=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -oE '[0-9]+%' | head -1 | tr -d '%')
    local mute=$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | grep -oE '(yes|no)')

    if [ -z "$vol" ]; then
        echo "$SYM_ERR|N/A|No audio"
        return
    fi

    if [ "$mute" = "yes" ]; then
        echo "$SYM_OFF|${vol}%|MUTED"
    else
        echo "$SYM_OK|${vol}%|Active"
    fi
}

dash_get_brightness() {
    if ! has_tool brightnessctl; then
        echo "$SYM_WARN|N/A|No backlight"
        return
    fi

    local brightness=$(brightnessctl -m 2>/dev/null | cut -d',' -f4 | tr -d '%')
    if [ -n "$brightness" ]; then
        echo "$SYM_OK|${brightness}%|"
    else
        echo "$SYM_WARN|N/A|"
    fi
}

dash_get_battery() {
    local bat_path=""
    for path in /sys/class/power_supply/BAT0 /sys/class/power_supply/BAT1; do
        if [ -f "$path/capacity" ]; then
            bat_path="$path"
            break
        fi
    done

    if [ -z "$bat_path" ]; then
        echo "$SYM_WARN|N/A|No battery"
        return
    fi

    local cap=$(cat "$bat_path/capacity" 2>/dev/null)
    local status=$(cat "$bat_path/status" 2>/dev/null)

    local sym="$SYM_BAT"
    local state="$status"

    case "$status" in
        Charging)
            sym="$SYM_BAT_CHRG"
            state="Charging"
            ;;
        Discharging)
            if [ "$cap" -le 20 ]; then
                sym="$SYM_WARN"
                state="Low!"
            else
                state="On battery"
            fi
            ;;
        Full)
            sym="$SYM_OK"
            state="Full"
            ;;
    esac

    echo "$sym|${cap}%|$state"
}

dash_get_cpu_load() {
    local load=$(uptime | sed 's/.*load average: //' | cut -d',' -f1 | xargs)
    local load_int=${load%.*}

    local sym="$SYM_OK"
    local state="Normal"

    if [ "$load_int" -ge 4 ]; then
        sym="$SYM_WARN"
        state="High load"
    elif [ "$load_int" -ge 2 ]; then
        state="Moderate"
    else
        state="Low"
    fi

    echo "$sym|$load|$state"
}

dash_get_memory() {
    local percent=$(get_memory_percent)
    local used=$(free -h | awk '/^Mem:/ {print $3}')
    local total=$(free -h | awk '/^Mem:/ {print $2}')

    local sym="$SYM_OK"
    local state="OK"

    if [ "$percent" -ge 90 ]; then
        sym="$SYM_WARN"
        state="Critical!"
    elif [ "$percent" -ge 75 ]; then
        sym="$SYM_WARN"
        state="High"
    fi

    echo "$sym|$used / $total|${percent}%"
}

dash_get_disk() {
    local percent=$(get_disk_percent)
    # df columns vary: find used and total from the numeric columns
    local df_line=$(df -h / | tail -1)
    local total=$(echo "$df_line" | awk '{print $1}')
    local used=$(echo "$df_line" | awk '{print $2}')

    # If first column looks like a device path, shift columns
    if echo "$total" | grep -qE "^/"; then
        total=$(echo "$df_line" | awk '{print $2}')
        used=$(echo "$df_line" | awk '{print $3}')
    fi

    local sym="$SYM_OK"
    local state="OK"

    if [ -n "$percent" ] && [ "$percent" -ge 90 ]; then
        sym="$SYM_WARN"
        state="Critical!"
    elif [ -n "$percent" ] && [ "$percent" -ge 75 ]; then
        sym="$SYM_WARN"
        state="High"
    fi

    echo "$sym|$used / $total|${percent}%"
}

dash_get_uptime() {
    local up=$(uptime | sed 's/.*up //' | sed 's/,.*user.*//' | xargs)
    echo "$SYM_OK|$up|"
}

# ============================================================================
# Progress Bar with Threshold Colors
# ============================================================================

make_status_bar() {
    local percent=$1
    local width=${2:-20}

    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    # Use different fill chars based on level
    local fill_char="█"
    local empty_char="░"

    printf "%s%s %3d%%" \
        "$(printf "${fill_char}%.0s" $(seq 1 $filled 2>/dev/null))" \
        "$(printf "${empty_char}%.0s" $(seq 1 $empty 2>/dev/null))" \
        "$percent"
}

# ============================================================================
# Dashboard Display
# ============================================================================

build_dashboard() {
    # Gather all data
    IFS='|' read -r wifi_sym wifi_val wifi_detail <<< "$(dash_get_wifi)"
    IFS='|' read -r bt_sym bt_val bt_detail <<< "$(dash_get_bluetooth)"
    IFS='|' read -r vol_sym vol_val vol_detail <<< "$(dash_get_volume)"
    IFS='|' read -r bright_sym bright_val bright_detail <<< "$(dash_get_brightness)"
    IFS='|' read -r bat_sym bat_val bat_detail <<< "$(dash_get_battery)"
    IFS='|' read -r cpu_sym cpu_val cpu_detail <<< "$(dash_get_cpu_load)"
    IFS='|' read -r mem_sym mem_val mem_detail <<< "$(dash_get_memory)"
    IFS='|' read -r disk_sym disk_val disk_detail <<< "$(dash_get_disk)"
    IFS='|' read -r up_sym up_val up_detail <<< "$(dash_get_uptime)"

    # Get numeric values for bars
    local mem_pct=$(get_memory_percent)
    local disk_pct=$(get_disk_percent)
    local vol_pct=$(echo "$vol_val" | tr -d '%')
    [ -z "$vol_pct" ] && vol_pct=0

    # Build formatted output
    cat << EOF

                     SYSTEM DASHBOARD

  CONNECTIVITY
  ├─ WiFi       $wifi_sym  $(printf "%-20s" "$wifi_val") $wifi_detail
  └─ Bluetooth  $bt_sym  $(printf "%-20s" "$bt_val") $bt_detail

  HARDWARE
  ├─ Volume     $vol_sym  $(printf "%-20s" "$vol_val") $vol_detail
  ├─ Brightness $bright_sym  $(printf "%-20s" "$bright_val") $bright_detail
  └─ Battery    $bat_sym  $(printf "%-20s" "$bat_val") $bat_detail

  SYSTEM RESOURCES
  ├─ CPU Load   $cpu_sym  $(printf "%-20s" "$cpu_val") $cpu_detail
  ├─ Memory     $mem_sym  $(make_status_bar $mem_pct 18)
  └─ Disk (/)   $disk_sym  $(make_status_bar $disk_pct 18)

  Uptime        $up_sym  $up_val


Legend: $SYM_OK Good  $SYM_WARN Warning  $SYM_OFF Off/Disabled  $SYM_ERR Error

         [Refresh]              [Menu]              [ESC] Exit
EOF
}

dashboard_menu() {
    while true; do
        local content=$(build_dashboard)

        dialog --backtitle "$BACKTITLE" \
            --title "[ Dashboard ]" \
            --yes-label "Refresh" \
            --no-label "Menu" \
            --timeout 10 \
            --yesno "$content" 26 63

        local exit_status=$?

        case $exit_status in
            0)  # Yes = Refresh
                continue
                ;;
            1)  # No = Go to Menu
                return
                ;;
            255) # Timeout or ESC
                continue
                ;;
        esac
    done
}

dashboard_menu

# Bluetooth Settings Module - Enhanced
# Device management with battery levels, trust status, and codec info

source "$MODULES_DIR/common.sh"

# ============================================================================
# Power & Status
# ============================================================================

get_power_status() {
    bluetoothctl show 2>/dev/null | grep "Powered:" | awk '{print $2}'
}

toggle_power() {
    local current=$(get_power_status)
    if [ "$current" = "yes" ]; then
        bluetoothctl power off > /dev/null 2>&1
    else
        bluetoothctl power on > /dev/null 2>&1
    fi
}

# ============================================================================
# Device Information
# ============================================================================

get_paired_devices() {
    bluetoothctl devices Paired 2>/dev/null
}

get_connected_devices() {
    bluetoothctl devices Connected 2>/dev/null
}

is_connected() {
    bluetoothctl info "$1" 2>/dev/null | grep -q "Connected: yes"
}

is_trusted() {
    bluetoothctl info "$1" 2>/dev/null | grep -q "Trusted: yes"
}

get_device_name() {
    local mac="$1"
    bluetoothctl info "$mac" 2>/dev/null | grep "Name:" | cut -d' ' -f2-
}

get_device_type() {
    local mac="$1"
    local icon=$(bluetoothctl info "$mac" 2>/dev/null | grep "Icon:" | awk '{print $2}')
    case "$icon" in
        audio-headset|audio-headphones) echo "Headphones" ;;
        audio-card) echo "Speaker" ;;
        input-keyboard) echo "Keyboard" ;;
        input-mouse) echo "Mouse" ;;
        input-gaming) echo "Controller" ;;
        phone) echo "Phone" ;;
        computer) echo "Computer" ;;
        *) echo "Device" ;;
    esac
}

get_device_battery() {
    local mac="$1"

    # Try bluetoothctl first
    local battery=$(bluetoothctl info "$mac" 2>/dev/null | grep "Battery Percentage:" | grep -oE "[0-9]+")

    # Try upower if bluetoothctl doesn't have it
    if [ -z "$battery" ] && has_tool upower; then
        local upower_path="/org/bluez/hci0/dev_$(echo $mac | tr ':' '_')"
        battery=$(upower -i "$upower_path" 2>/dev/null | grep "percentage:" | grep -oE "[0-9]+")
    fi

    if [ -n "$battery" ]; then
        echo "${battery}%"
    else
        echo ""
    fi
}

get_audio_codec() {
    local mac="$1"

    if has_tool pactl; then
        # Look for bluetooth codec in PulseAudio/PipeWire
        local codec=$(pactl list 2>/dev/null | grep -A5 "bluez" | grep -i "codec" | head -1 | awk -F'=' '{print $2}' | tr -d ' "')
        [ -n "$codec" ] && echo "$codec" && return
    fi

    echo ""
}

# ============================================================================
# Device Actions
# ============================================================================

connect_device() {
    local mac="$1"
    show_info "Connecting to $mac..."
    bluetoothctl connect "$mac" > /dev/null 2>&1
    sleep 1
    if is_connected "$mac"; then
        show_message "Connected successfully!" "Bluetooth"
    else
        show_message "Connection failed.\nMake sure the device is in pairing mode." "Error"
    fi
}

disconnect_device() {
    local mac="$1"
    bluetoothctl disconnect "$mac" > /dev/null 2>&1
    show_info "Disconnected"
}

remove_device() {
    local mac="$1"
    local name=$(get_device_name "$mac")
    if confirm "Remove $name?\n\nYou will need to pair again."; then
        bluetoothctl remove "$mac" > /dev/null 2>&1
        show_info "Device removed"
    fi
}

trust_device() {
    local mac="$1"
    bluetoothctl trust "$mac" > /dev/null 2>&1
    show_info "Device trusted (will auto-connect)"
}

untrust_device() {
    local mac="$1"
    bluetoothctl untrust "$mac" > /dev/null 2>&1
    show_info "Device untrusted"
}

# ============================================================================
# Device Menu
# ============================================================================

device_action() {
    local mac="$1"
    local name=$(get_device_name "$mac")
    local type=$(get_device_type "$mac")
    local battery=$(get_device_battery "$mac")
    local connected=$(is_connected "$mac" && echo "Yes" || echo "No")
    local trusted=$(is_trusted "$mac" && echo "Yes" || echo "No")
    local codec=$(get_audio_codec "$mac")

    while true; do
        # Build info string
        local info="Type: $type"
        [ -n "$battery" ] && info="$info\nBattery: $battery"
        info="$info\nConnected: $connected\nTrusted: $trusted"
        [ -n "$codec" ] && info="$info\nCodec: $codec"

        if is_connected "$mac"; then
            choice=$(dialog --backtitle "$BACKTITLE" \
                --title "[ $name ]" \
                --menu "$info" 16 55 5 \
                1 "Disconnect" \
                2 "Toggle Trust (Auto-connect)" \
                3 "Remove Device" \
                4 "Device Info" \
                2>&1 >/dev/tty)
        else
            choice=$(dialog --backtitle "$BACKTITLE" \
                --title "[ $name ]" \
                --menu "$info" 16 55 5 \
                1 "Connect" \
                2 "Toggle Trust (Auto-connect)" \
                3 "Remove Device" \
                4 "Device Info" \
                2>&1 >/dev/tty)
        fi

        local exit_status=$?
        [ $exit_status -ne 0 ] && return

        case $choice in
            1)
                if is_connected "$mac"; then
                    disconnect_device "$mac"
                else
                    connect_device "$mac"
                fi
                # Update status
                connected=$(is_connected "$mac" && echo "Yes" || echo "No")
                ;;
            2)
                if is_trusted "$mac"; then
                    untrust_device "$mac"
                else
                    trust_device "$mac"
                fi
                trusted=$(is_trusted "$mac" && echo "Yes" || echo "No")
                ;;
            3)
                remove_device "$mac"
                return
                ;;
            4)
                show_device_info "$mac"
                ;;
        esac
    done
}

show_device_info() {
    local mac="$1"
    local info=$(bluetoothctl info "$mac" 2>/dev/null)

    dialog --backtitle "$BACKTITLE" \
        --title "[ Device Info ]" \
        --msgbox "$info" 20 70
}

# ============================================================================
# Paired Devices Menu
# ============================================================================

show_paired_devices() {
    devices=$(get_paired_devices)
    if [ -z "$devices" ]; then
        show_message "No paired devices found.\n\nUse 'Scan for Devices' to find new devices." "Info"
        return
    fi

    while true; do
        # Refresh device list
        devices=$(get_paired_devices)
        [ -z "$devices" ] && return

        # Prepare menu data in "mac:name status" format
        local menu_data=""
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            mac=$(echo "$line" | awk '{print $2}')
            name=$(echo "$line" | cut -d' ' -f3-)

            # Build status string
            local status=""
            if is_connected "$mac"; then
                status="[Connected]"
            fi

            local battery=$(get_device_battery "$mac")
            [ -n "$battery" ] && status="$status [Bat: $battery]"

            if is_trusted "$mac"; then
                status="$status [Trusted]"
            fi

            menu_data="${menu_data}${mac}:${name} ${status}\n"
        done <<< "$devices"

        local selected_mac
        selected_mac=$(build_dynamic_menu "Paired Devices" "Select device:" "$menu_data" ":" 16 65)
        [ $? -ne 0 ] && return

        device_action "$selected_mac"
    done
}

# ============================================================================
# Scan & Pair
# ============================================================================

scan_devices() {
    dialog --backtitle "$BACKTITLE" \
        --infobox "Scanning for devices...\n\nPlease wait 5 seconds.\nMake sure your device is in pairing mode." 7 50

    bluetoothctl --timeout 5 scan on > /dev/null 2>&1

    # Get all discovered devices (includes paired)
    devices=$(bluetoothctl devices 2>/dev/null)

    if [ -z "$devices" ]; then
        show_message "No devices found.\n\nMake sure:\n- Device is in pairing mode\n- Bluetooth is enabled on both devices" "Scan"
        return
    fi

    # Prepare menu data in "mac:name" format
    local menu_data=""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        mac=$(echo "$line" | awk '{print $2}')
        name=$(echo "$line" | cut -d' ' -f3-)

        # Check if already paired
        local paired=""
        if bluetoothctl devices Paired 2>/dev/null | grep -q "$mac"; then
            paired=" [Paired]"
        fi

        menu_data="${menu_data}${mac}:${name}${paired}\n"
    done <<< "$devices"

    local selected_mac
    selected_mac=$(build_dynamic_menu "Found Devices" "Select to pair:" "$menu_data" ":" 16 60)
    [ $? -ne 0 ] && return

    # Check if already paired
    if bluetoothctl devices Paired 2>/dev/null | grep -q "$selected_mac"; then
        show_message "Device is already paired.\n\nGo to Paired Devices to connect." "Info"
        return
    fi

    pair_device "$selected_mac"
}

pair_device() {
    local mac="$1"

    dialog --backtitle "$BACKTITLE" \
        --infobox "Pairing with $mac...\n\nCheck if device needs confirmation." 6 50

    # Try to pair
    bluetoothctl pair "$mac" 2>&1

    sleep 2

    # Trust and connect
    bluetoothctl trust "$mac" > /dev/null 2>&1

    dialog --backtitle "$BACKTITLE" \
        --infobox "Connecting..." 4 30

    bluetoothctl connect "$mac" > /dev/null 2>&1

    sleep 1

    if is_connected "$mac"; then
        show_message "Device paired and connected!" "Success"
    else
        show_message "Pairing attempted.\n\nIf it didn't work:\n- Check device is in pairing mode\n- Try removing and re-pairing\n- Check for PIN prompt on device" "Pairing"
    fi
}

# ============================================================================
# Quick Connect
# ============================================================================

quick_connect_menu() {
    local devices=$(get_paired_devices)

    if [ -z "$devices" ]; then
        show_message "No paired devices." "Info"
        return
    fi

    # Only show disconnected devices - prepare menu data
    local menu_data=""
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local mac=$(echo "$line" | awk '{print $2}')
        local name=$(echo "$line" | cut -d' ' -f3-)

        if ! is_connected "$mac"; then
            menu_data="${menu_data}${mac}:${name}\n"
        fi
    done <<< "$devices"

    if [ -z "$menu_data" ]; then
        show_message "All paired devices are connected." "Info"
        return
    fi

    local selected
    selected=$(build_dynamic_menu "Quick Connect" "Select device:" "$menu_data" ":" 14 55)
    [ $? -ne 0 ] && return

    connect_device "$selected"
}

# ============================================================================
# Main Bluetooth Menu
# ============================================================================

bluetooth_menu() {
    if ! has_tool bluetoothctl; then
        show_message "bluetoothctl not found.\n\nInstall with:\n  sudo apk add bluez" "Error"
        return
    fi

    while true; do
        local power=$(get_power_status)
        [ "$power" = "yes" ] && power_status="ON" || power_status="OFF"

        # Get connected device count
        local connected_count=$(get_connected_devices | wc -l)
        local connected_info=""
        if [ "$connected_count" -gt 0 ] && [ "$power" = "yes" ]; then
            local first_connected=$(get_connected_devices | head -1 | cut -d' ' -f3-)
            connected_info="\nConnected: $first_connected"
            [ "$connected_count" -gt 1 ] && connected_info="$connected_info (+$((connected_count-1)) more)"
        fi

        choice=$(dialog --backtitle "$BACKTITLE" \
            --title "[ Bluetooth Settings ]" \
            --menu "Bluetooth: $power_status$connected_info" 16 55 7 \
            1 "Toggle Power ($power_status)" \
            2 "Paired Devices" \
            3 "Quick Connect" \
            4 "Scan for Devices" \
            5 "Disconnect All" \
            6 "Open bluetoothctl" \
            2>&1 >/dev/tty)

        local exit_status=$?
        [ $exit_status -ne 0 ] && return

        case $choice in
            1) toggle_power ;;
            2) show_paired_devices ;;
            3) quick_connect_menu ;;
            4) scan_devices ;;
            5)
                if confirm "Disconnect all devices?"; then
                    while IFS= read -r line; do
                        local mac=$(echo "$line" | awk '{print $2}')
                        bluetoothctl disconnect "$mac" > /dev/null 2>&1
                    done <<< "$(get_connected_devices)"
                    show_info "All devices disconnected"
                fi
                ;;
            6) clear; bluetoothctl ;;
        esac
    done
}

bluetooth_menu

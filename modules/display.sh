# Display Settings Module
# Resolution, rotation, multi-monitor, night mode, brightness

source "$MODULES_DIR/common.sh"

# ============================================================================
# Display Detection
# ============================================================================

get_displays() {
    local randr=$(get_randr_cmd)
    [ -z "$randr" ] && return 1

    if [ "$randr" = "xrandr" ]; then
        xrandr --query 2>/dev/null | grep " connected" | cut -d' ' -f1
    else
        wlr-randr 2>/dev/null | grep "^[^ ]" | cut -d' ' -f1
    fi
}

get_current_resolution() {
    local display="$1"
    local randr=$(get_randr_cmd)

    if [ "$randr" = "xrandr" ]; then
        xrandr --query 2>/dev/null | grep -A1 "^$display connected" | tail -1 | awk '{print $1}'
    else
        wlr-randr 2>/dev/null | grep -A3 "^$display" | grep "current" | awk '{print $1}'
    fi
}

get_available_resolutions() {
    local display="$1"
    local randr=$(get_randr_cmd)

    if [ "$randr" = "xrandr" ]; then
        xrandr --query 2>/dev/null | sed -n "/^$display connected/,/^[^ ]/p" | grep -E "^\s+" | awk '{print $1}' | sort -rn -t'x' -k1 | uniq
    else
        wlr-randr 2>/dev/null | sed -n "/^$display/,/^[^ ]/p" | grep -E "^\s+[0-9]+x" | awk '{print $1}' | sort -rn -t'x' -k1 | uniq
    fi
}

get_current_rotation() {
    local display="$1"
    local randr=$(get_randr_cmd)

    if [ "$randr" = "xrandr" ]; then
        local info=$(xrandr --query 2>/dev/null | grep "^$display connected")
        if echo "$info" | grep -q "left"; then
            echo "left"
        elif echo "$info" | grep -q "right"; then
            echo "right"
        elif echo "$info" | grep -q "inverted"; then
            echo "inverted"
        else
            echo "normal"
        fi
    else
        wlr-randr 2>/dev/null | sed -n "/^$display/,/^[^ ]/p" | grep "Transform:" | awk '{print $2}'
    fi
}

# ============================================================================
# Display Actions
# ============================================================================

set_resolution() {
    local display="$1"
    local resolution="$2"
    local randr=$(get_randr_cmd)

    if [ "$randr" = "xrandr" ]; then
        xrandr --output "$display" --mode "$resolution" 2>/dev/null
    else
        wlr-randr --output "$display" --mode "$resolution" 2>/dev/null
    fi
}

set_rotation() {
    local display="$1"
    local rotation="$2"
    local randr=$(get_randr_cmd)

    if [ "$randr" = "xrandr" ]; then
        xrandr --output "$display" --rotate "$rotation" 2>/dev/null
    else
        wlr-randr --output "$display" --transform "$rotation" 2>/dev/null
    fi
}

set_primary() {
    local display="$1"
    local randr=$(get_randr_cmd)

    if [ "$randr" = "xrandr" ]; then
        xrandr --output "$display" --primary 2>/dev/null
    else
        show_message "Primary display not supported on Wayland.\nUse your compositor settings." "Note"
    fi
}

toggle_display() {
    local display="$1"
    local action="$2"
    local randr=$(get_randr_cmd)

    if [ "$randr" = "xrandr" ]; then
        if [ "$action" = "off" ]; then
            xrandr --output "$display" --off 2>/dev/null
        else
            xrandr --output "$display" --auto 2>/dev/null
        fi
    else
        if [ "$action" = "off" ]; then
            wlr-randr --output "$display" --off 2>/dev/null
        else
            wlr-randr --output "$display" --on 2>/dev/null
        fi
    fi
}

# ============================================================================
# Night Mode (Redshift)
# ============================================================================

get_night_mode_status() {
    if is_process_running redshift; then
        echo "ON"
    else
        echo "OFF"
    fi
}

night_mode_on() {
    local temp="${1:-3500}"
    if has_tool redshift; then
        # Kill existing redshift first
        pkill -x redshift 2>/dev/null
        sleep 0.5
        redshift -O "$temp" 2>/dev/null &
        show_info "Night mode enabled (${temp}K)"
    else
        show_message "redshift is not installed.\n\nInstall with:\n  sudo apk add redshift" "Missing Tool"
    fi
}

night_mode_off() {
    if has_tool redshift; then
        redshift -x 2>/dev/null
        pkill -x redshift 2>/dev/null
        show_info "Night mode disabled"
    fi
}

night_mode_submenu() {
    while true; do
        local status=$(get_night_mode_status)

        choice=$(dialog --backtitle "$BACKTITLE" \
            --title "[ Night Mode ]" \
            --menu "Status: $status" 14 50 5 \
            1 "Enable (3500K - Warm)" \
            2 "Enable (4500K - Moderate)" \
            3 "Enable (5500K - Slight)" \
            4 "Disable" \
            5 "Custom Temperature" \
            2>&1 >/dev/tty)

        local exit_status=$?
        [ $exit_status -ne 0 ] && return

        case $choice in
            1) night_mode_on 3500 ;;
            2) night_mode_on 4500 ;;
            3) night_mode_on 5500 ;;
            4) night_mode_off ;;
            5)
                local temp=$(get_input "Enter color temperature (2500-6500):" "Temperature" "4000")
                [ -n "$temp" ] && night_mode_on "$temp"
                ;;
        esac
    done
}

# ============================================================================
# Display Configuration Menu
# ============================================================================

display_config_menu() {
    local display="$1"
    local current_res=$(get_current_resolution "$display")
    local current_rot=$(get_current_rotation "$display")

    while true; do
        choice=$(dialog --backtitle "$BACKTITLE" \
            --title "[ $display ]" \
            --menu "Resolution: $current_res\nRotation: $current_rot" 14 50 5 \
            1 "Change Resolution" \
            2 "Change Rotation" \
            3 "Set as Primary" \
            4 "Turn Off Display" \
            5 "Turn On Display" \
            2>&1 >/dev/tty)

        local exit_status=$?
        [ $exit_status -ne 0 ] && return

        case $choice in
            1) resolution_menu "$display" ;;
            2) rotation_menu "$display" ;;
            3) set_primary "$display" ;;
            4)
                if confirm "Turn off $display?"; then
                    toggle_display "$display" off
                fi
                ;;
            5) toggle_display "$display" on ;;
        esac

        # Update current values
        current_res=$(get_current_resolution "$display")
        current_rot=$(get_current_rotation "$display")
    done
}

resolution_menu() {
    local display="$1"
    local resolutions=$(get_available_resolutions "$display")

    if [ -z "$resolutions" ]; then
        show_message "No resolutions available for $display" "Error"
        return
    fi

    local choice
    choice=$(build_simple_menu "Select Resolution" "Choose resolution for $display:" "$resolutions" 18 50)
    [ $? -ne 0 ] && return

    # Extract the selected resolution (choice is the index, we need the actual line)
    local selected=$(echo "$resolutions" | sed -n "${choice}p")
    set_resolution "$display" "$selected"
}

rotation_menu() {
    local display="$1"

    choice=$(dialog --backtitle "$BACKTITLE" \
        --title "[ Rotation ]" \
        --menu "Select rotation for $display:" 12 50 4 \
        1 "Normal" \
        2 "Left (90°)" \
        3 "Right (270°)" \
        4 "Inverted (180°)" \
        2>&1 >/dev/tty)

    [ -z "$choice" ] && return

    case $choice in
        1) set_rotation "$display" "normal" ;;
        2) set_rotation "$display" "left" ;;
        3) set_rotation "$display" "right" ;;
        4) set_rotation "$display" "inverted" ;;
    esac
}

# ============================================================================
# Main Display Menu
# ============================================================================

display_menu() {
    local randr=$(get_randr_cmd)

    if [ -z "$randr" ] || ! has_tool "$randr"; then
        show_message "No display server detected.\n\nThis module requires X11 (xrandr) or Wayland (wlr-randr)." "Error"
        return
    fi

    while true; do
        local displays=$(get_displays)
        local brightness=$(get_brightness)
        local night_status=$(get_night_mode_status)

        # Build menu with displays
        local menu_items=""
        local i=1

        # Add each connected display
        while IFS= read -r disp; do
            [ -z "$disp" ] && continue
            local res=$(get_current_resolution "$disp")
            menu_items="$menu_items $i \"$disp ($res)\" "
            eval "display_$i=\"$disp\""
            i=$((i + 1))
        done <<< "$displays"

        # Add standard options
        menu_items="$menu_items B \"Brightness: ${brightness}%\" "
        menu_items="$menu_items N \"Night Mode: $night_status\" "
        menu_items="$menu_items D \"Detect Displays\" "

        choice=$(eval "dialog --backtitle '$BACKTITLE' \
            --title '[ Display Settings ]' \
            --menu 'Select option:' 18 55 10 $menu_items" 2>&1 >/dev/tty)

        local exit_status=$?
        [ $exit_status -ne 0 ] && return

        case $choice in
            B) brightness_submenu ;;
            N) night_mode_submenu ;;
            D)
                show_info "Detecting displays..."
                # Force refresh
                if [ "$randr" = "xrandr" ]; then
                    xrandr --auto 2>/dev/null
                fi
                ;;
            [0-9]*)
                eval "selected_display=\$display_$choice"
                display_config_menu "$selected_display"
                ;;
        esac
    done
}

display_menu

# Audio Settings Module - Enhanced
# Output/input devices, per-app volume, audio profiles

source "$MODULES_DIR/common.sh"

# ============================================================================
# Output (Sink) Functions
# ============================================================================

get_volume() {
    pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -o '[0-9]*%' | head -1 | tr -d '%'
}

get_mute() {
    pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | grep -o 'yes\|no'
}

set_volume() {
    local value="$1"
    pactl set-sink-volume @DEFAULT_SINK@ "$value" 2>/dev/null
}

toggle_mute() {
    pactl set-sink-mute @DEFAULT_SINK@ toggle 2>/dev/null
}

get_sinks() {
    pactl list sinks short 2>/dev/null | awk '{print $1 ":" $2}'
}

get_default_sink() {
    pactl get-default-sink 2>/dev/null
}

get_sink_name() {
    local sink="$1"
    pactl list sinks 2>/dev/null | grep -A1 "Name: $sink" | grep "Description:" | cut -d':' -f2- | xargs
}

set_default_sink() {
    local sink="$1"
    pactl set-default-sink "$sink" 2>/dev/null
}

# ============================================================================
# Input (Source) Functions
# ============================================================================

get_mic_volume() {
    pactl get-source-volume @DEFAULT_SOURCE@ 2>/dev/null | grep -o '[0-9]*%' | head -1 | tr -d '%'
}

get_mic_mute() {
    pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null | grep -o 'yes\|no'
}

set_mic_volume() {
    local value="$1"
    pactl set-source-volume @DEFAULT_SOURCE@ "$value" 2>/dev/null
}

toggle_mic_mute() {
    pactl set-source-mute @DEFAULT_SOURCE@ toggle 2>/dev/null
}

get_sources() {
    pactl list sources short 2>/dev/null | grep -v "\.monitor$" | awk '{print $1 ":" $2}'
}

get_default_source() {
    pactl get-default-source 2>/dev/null
}

get_source_name() {
    local source="$1"
    pactl list sources 2>/dev/null | grep -A1 "Name: $source" | grep "Description:" | cut -d':' -f2- | xargs
}

set_default_source() {
    local source="$1"
    pactl set-default-source "$source" 2>/dev/null
}

# ============================================================================
# Per-Application Volume
# ============================================================================

get_sink_inputs() {
    # Returns: index, app_name, volume
    pactl list sink-inputs 2>/dev/null | awk '
        /Sink Input #/ { idx = $3; gsub(/#/, "", idx) }
        /application.name/ { name = $0; gsub(/.*= "/, "", name); gsub(/".*/, "", name) }
        /Volume:.*front-left/ {
            vol = $0; gsub(/.*\//, "", vol); gsub(/%.*/, "", vol)
            print idx ":" name ":" vol
        }
    '
}

set_app_volume() {
    local index="$1"
    local volume="$2"
    pactl set-sink-input-volume "$index" "$volume" 2>/dev/null
}

mute_app() {
    local index="$1"
    pactl set-sink-input-mute "$index" toggle 2>/dev/null
}

# ============================================================================
# Audio Profiles (Cards)
# ============================================================================

get_cards() {
    pactl list cards short 2>/dev/null | awk '{print $1 ":" $2}'
}

get_card_profiles() {
    local card="$1"
    pactl list cards 2>/dev/null | sed -n "/Name: $card/,/^Card/p" | grep "output:" | awk -F: '{print $1}' | xargs
}

get_active_profile() {
    local card="$1"
    pactl list cards 2>/dev/null | sed -n "/Name: $card/,/^Card/p" | grep "Active Profile:" | cut -d':' -f2 | xargs
}

set_card_profile() {
    local card="$1"
    local profile="$2"
    pactl set-card-profile "$card" "$profile" 2>/dev/null
}

# ============================================================================
# Volume Control Submenu
# ============================================================================

volume_menu() {
    while true; do
        local vol=$(get_volume)
        local mute=$(get_mute)
        [ "$mute" = "yes" ] && mute_status="[MUTED]" || mute_status=""

        choice=$(dialog --backtitle "$BACKTITLE" \
            --title "[ Volume Control ]" \
            --menu "Volume: ${vol}% ${mute_status}" 16 50 7 \
            1 "Increase (+10%)" \
            2 "Decrease (-10%)" \
            3 "Set to 25%" \
            4 "Set to 50%" \
            5 "Set to 100%" \
            6 "Toggle Mute" \
            7 "Custom Volume" \
            2>&1 >/dev/tty)

        local exit_status=$?
        [ $exit_status -ne 0 ] && return

        case $choice in
            1) set_volume +10% ;;
            2) set_volume -10% ;;
            3) set_volume 25% ;;
            4) set_volume 50% ;;
            5) set_volume 100% ;;
            6) toggle_mute ;;
            7)
                local custom=$(get_input "Enter volume (0-150):" "Volume" "$vol")
                [ -n "$custom" ] && set_volume "${custom}%"
                ;;
        esac
    done
}

# ============================================================================
# Output Device Menu
# ============================================================================

output_device_menu() {
    while true; do
        local default=$(get_default_sink)
        local sinks=$(get_sinks)

        if [ -z "$sinks" ]; then
            show_message "No output devices found." "Error"
            return
        fi

        local menu_items=""
        local i=1
        while IFS=':' read -r idx name; do
            [ -z "$name" ] && continue
            local desc=$(get_sink_name "$name")
            [ -z "$desc" ] && desc="$name"

            local marker=""
            [ "$name" = "$default" ] && marker=" [DEFAULT]"

            menu_items="$menu_items $i \"$desc$marker\" "
            eval "sink_$i=\"$name\""
            i=$((i + 1))
        done <<< "$sinks"

        choice=$(eval "dialog --backtitle '$BACKTITLE' \
            --title '[ Output Devices ]' \
            --menu 'Select output device:' 15 65 8 $menu_items" 2>&1 >/dev/tty)

        [ -z "$choice" ] && return

        eval "selected=\$sink_$choice"
        set_default_sink "$selected"
        show_info "Output set to: $selected"
    done
}

# ============================================================================
# Input Device Menu
# ============================================================================

input_device_menu() {
    while true; do
        local mic_vol=$(get_mic_volume)
        local mic_mute=$(get_mic_mute)
        [ "$mic_mute" = "yes" ] && mute_status="[MUTED]" || mute_status=""

        choice=$(dialog --backtitle "$BACKTITLE" \
            --title "[ Input (Microphone) ]" \
            --menu "Mic Volume: ${mic_vol}% ${mute_status}" 14 55 5 \
            1 "Select Input Device" \
            2 "Increase Mic (+10%)" \
            3 "Decrease Mic (-10%)" \
            4 "Toggle Mic Mute" \
            5 "Set Mic Volume" \
            2>&1 >/dev/tty)

        local exit_status=$?
        [ $exit_status -ne 0 ] && return

        case $choice in
            1) select_input_device ;;
            2) set_mic_volume +10% ;;
            3) set_mic_volume -10% ;;
            4) toggle_mic_mute ;;
            5)
                local custom=$(get_input "Enter mic volume (0-150):" "Mic Volume" "$mic_vol")
                [ -n "$custom" ] && set_mic_volume "${custom}%"
                ;;
        esac
    done
}

select_input_device() {
    local default=$(get_default_source)
    local sources=$(get_sources)

    if [ -z "$sources" ]; then
        show_message "No input devices found." "Error"
        return
    fi

    local menu_items=""
    local i=1
    while IFS=':' read -r idx name; do
        [ -z "$name" ] && continue
        local desc=$(get_source_name "$name")
        [ -z "$desc" ] && desc="$name"

        local marker=""
        [ "$name" = "$default" ] && marker=" [DEFAULT]"

        menu_items="$menu_items $i \"$desc$marker\" "
        eval "source_$i=\"$name\""
        i=$((i + 1))
    done <<< "$sources"

    choice=$(eval "dialog --backtitle '$BACKTITLE' \
        --title '[ Input Devices ]' \
        --menu 'Select input device:' 15 65 8 $menu_items" 2>&1 >/dev/tty)

    [ -z "$choice" ] && return

    eval "selected=\$source_$choice"
    set_default_source "$selected"
    show_info "Input set to: $selected"
}

# ============================================================================
# Per-App Volume Menu
# ============================================================================

per_app_menu() {
    while true; do
        local inputs=$(get_sink_inputs)

        if [ -z "$inputs" ]; then
            show_message "No applications are currently playing audio." "Info"
            return
        fi

        local menu_items=""
        local i=1
        while IFS=':' read -r idx name vol; do
            [ -z "$idx" ] && continue
            menu_items="$menu_items $i \"$name (${vol}%)\" "
            eval "app_idx_$i=\"$idx\""
            eval "app_name_$i=\"$name\""
            i=$((i + 1))
        done <<< "$inputs"

        choice=$(eval "dialog --backtitle '$BACKTITLE' \
            --title '[ Per-Application Volume ]' \
            --menu 'Select application:' 15 55 8 $menu_items" 2>&1 >/dev/tty)

        [ -z "$choice" ] && return

        eval "selected_idx=\$app_idx_$choice"
        eval "selected_name=\$app_name_$choice"

        app_volume_menu "$selected_idx" "$selected_name"
    done
}

app_volume_menu() {
    local idx="$1"
    local name="$2"

    while true; do
        choice=$(dialog --backtitle "$BACKTITLE" \
            --title "[ $name ]" \
            --menu "Adjust volume:" 14 50 5 \
            1 "Increase (+10%)" \
            2 "Decrease (-10%)" \
            3 "Set to 50%" \
            4 "Set to 100%" \
            5 "Mute/Unmute" \
            2>&1 >/dev/tty)

        local exit_status=$?
        [ $exit_status -ne 0 ] && return

        case $choice in
            1) set_app_volume "$idx" +10% ;;
            2) set_app_volume "$idx" -10% ;;
            3) set_app_volume "$idx" 50% ;;
            4) set_app_volume "$idx" 100% ;;
            5) mute_app "$idx" ;;
        esac
    done
}

# ============================================================================
# PipeWire Pipeline Control
# ============================================================================

AUDIO_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/termos/audio_enabled"

is_pipewire_running() {
    pgrep -x pipewire >/dev/null 2>&1
}

is_audio_enabled_on_boot() {
    # Audio is enabled by default if config file doesn't exist or doesn't say "disabled"
    if [ ! -f "$AUDIO_CONFIG" ] || [ "$(cat "$AUDIO_CONFIG" 2>/dev/null)" != "disabled" ]; then
        return 0
    fi
    return 1
}

get_pipewire_status() {
    if is_pipewire_running; then
        echo "Running"
    else
        echo "Stopped"
    fi
}

get_boot_status() {
    if is_audio_enabled_on_boot; then
        echo "Enabled"
    else
        echo "Disabled"
    fi
}

start_pipewire() {
    if is_pipewire_running; then
        return 0
    fi
    pipewire >/dev/null 2>&1 &
    sleep 0.2
    pipewire-pulse >/dev/null 2>&1 &
    wireplumber >/dev/null 2>&1 &
}

stop_pipewire() {
    pkill -x wireplumber 2>/dev/null
    pkill -x pipewire-pulse 2>/dev/null
    pkill -x pipewire 2>/dev/null
}

enable_audio_on_boot() {
    mkdir -p "$(dirname "$AUDIO_CONFIG")"
    echo "enabled" > "$AUDIO_CONFIG"
}

disable_audio_on_boot() {
    mkdir -p "$(dirname "$AUDIO_CONFIG")"
    echo "disabled" > "$AUDIO_CONFIG"
}

pipewire_menu() {
    while true; do
        local status=$(get_pipewire_status)
        local boot_status=$(get_boot_status)

        choice=$(dialog --backtitle "$BACKTITLE" \
            --title "[ PipeWire Control ]" \
            --menu "Current: $status | On Boot: $boot_status" 16 60 7 \
            1 "Start PipeWire Now" \
            2 "Stop PipeWire Now" \
            3 "Restart PipeWire" \
            4 "Enable Audio on Boot" \
            5 "Disable Audio on Boot" \
            6 "Toggle Boot Setting" \
            2>&1 >/dev/tty)

        local exit_status=$?
        [ $exit_status -ne 0 ] && return

        case $choice in
            1)
                start_pipewire
                show_info "PipeWire started"
                ;;
            2)
                stop_pipewire
                show_info "PipeWire stopped"
                ;;
            3)
                stop_pipewire
                sleep 0.3
                start_pipewire
                show_info "PipeWire restarted"
                ;;
            4)
                enable_audio_on_boot
                show_info "Audio will start on boot"
                ;;
            5)
                disable_audio_on_boot
                show_info "Audio disabled on boot"
                ;;
            6)
                if is_audio_enabled_on_boot; then
                    disable_audio_on_boot
                    show_info "Audio disabled on boot"
                else
                    enable_audio_on_boot
                    show_info "Audio enabled on boot"
                fi
                ;;
        esac
    done
}

# ============================================================================
# Audio Profiles Menu
# ============================================================================

profiles_menu() {
    local cards=$(get_cards)

    if [ -z "$cards" ]; then
        show_message "No audio cards found." "Error"
        return
    fi

    # For simplicity, work with the first card
    local first_card=$(echo "$cards" | head -1 | cut -d':' -f2)
    local active=$(get_active_profile "$first_card")

    # Get available profiles
    local profiles=$(pactl list cards 2>/dev/null | sed -n "/Name: $first_card/,/^Card/p" | grep -E "^\s+(output:|off)" | awk '{print $1}')

    if [ -z "$profiles" ]; then
        show_message "No profiles available for this card." "Error"
        return
    fi

    local menu_items=""
    local i=1
    while IFS= read -r profile; do
        [ -z "$profile" ] && continue
        local marker=""
        [ "$profile" = "$active" ] && marker=" [ACTIVE]"
        menu_items="$menu_items $i \"$profile$marker\" "
        eval "profile_$i=\"$profile\""
        i=$((i + 1))
    done <<< "$profiles"

    choice=$(eval "dialog --backtitle '$BACKTITLE' \
        --title '[ Audio Profiles ]' \
        --menu 'Select profile:' 15 60 8 $menu_items" 2>&1 >/dev/tty)

    [ -z "$choice" ] && return

    eval "selected=\$profile_$choice"
    set_card_profile "$first_card" "$selected"
    show_info "Profile changed to: $selected"
}

# ============================================================================
# Main Audio Menu
# ============================================================================

audio_menu() {
    if ! has_tool pactl; then
        show_message "PulseAudio/PipeWire not found.\n\nThis module requires pactl." "Error"
        return
    fi

    while true; do
        local vol=$(get_volume)
        local mute=$(get_mute)
        [ "$mute" = "yes" ] && mute_status="[MUTED]" || mute_status=""

        local default_sink=$(get_default_sink)
        local sink_desc=$(get_sink_name "$default_sink")
        [ -z "$sink_desc" ] && sink_desc="$default_sink"

        local pw_status=$(get_pipewire_status)
        local boot_status=$(get_boot_status)

        choice=$(dialog --backtitle "$BACKTITLE" \
            --title "[ Audio Settings ]" \
            --menu "Volume: ${vol}% ${mute_status}\nOutput: $sink_desc\nPipeWire: $pw_status | Boot: $boot_status" 20 60 10 \
            1 "Volume Control" \
            2 "Output Device" \
            3 "Input (Microphone)" \
            4 "Per-Application Volume" \
            5 "Audio Profiles" \
            6 "PipeWire Control" \
            7 "Quick: Increase (+10%)" \
            8 "Quick: Decrease (-10%)" \
            9 "Quick: Toggle Mute" \
            10 "Open pulsemixer" \
            2>&1 >/dev/tty)

        local exit_status=$?
        [ $exit_status -ne 0 ] && return

        case $choice in
            1) volume_menu ;;
            2) output_device_menu ;;
            3) input_device_menu ;;
            4) per_app_menu ;;
            5) profiles_menu ;;
            6) pipewire_menu ;;
            7) set_volume +10% ;;
            8) set_volume -10% ;;
            9) toggle_mute ;;
            10) clear; pulsemixer 2>/dev/null || show_message "pulsemixer not installed" "Error" ;;
        esac
    done
}

audio_menu

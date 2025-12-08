# Brightness Settings Module

get_brightness() {
    brightnessctl -m | cut -d',' -f4 | tr -d '%'
}

brightness_menu() {
    while true; do
        current=$(get_brightness)

        choice=$(dialog --backtitle "TermOS Control Center" \
            --title "[ Display Brightness ]" \
            --menu "Current: ${current}%\n\nSelect action:" 16 50 6 \
            1 "Increase (+10%)" \
            2 "Decrease (-10%)" \
            3 "Set to 25%" \
            4 "Set to 50%" \
            5 "Set to 75%" \
            6 "Set to 100%" \
            2>&1 >/dev/tty)

        exit_status=$?
        [ $exit_status -ne 0 ] && return

        case $choice in
            1) brightnessctl set +10% > /dev/null ;;
            2) brightnessctl set 10%- > /dev/null ;;
            3) brightnessctl set 25% > /dev/null ;;
            4) brightnessctl set 50% > /dev/null ;;
            5) brightnessctl set 75% > /dev/null ;;
            6) brightnessctl set 100% > /dev/null ;;
        esac
    done
}

brightness_menu

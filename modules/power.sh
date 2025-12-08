# Power Options Module

power_menu() {
    choice=$(dialog --backtitle "TermOS Control Center" \
        --title "[ Power Options ]" \
        --menu "Select action:" 12 50 4 \
        1 "Lock Screen" \
        2 "Reboot" \
        3 "Shutdown" \
        4 "Back" \
        2>&1 >/dev/tty)

    exit_status=$?
    [ $exit_status -ne 0 ] && return

    case $choice in
        1)
            clear
            pkill -USR1 term39
            ;;
        2)
            dialog --backtitle "TermOS Control Center" \
                --title "Confirm Reboot" \
                --yesno "Are you sure you want to reboot?" 7 40
            [ $? -eq 0 ] && sudo reboot
            ;;
        3)
            dialog --backtitle "TermOS Control Center" \
                --title "Confirm Shutdown" \
                --yesno "Are you sure you want to shutdown?" 7 40
            [ $? -eq 0 ] && sudo poweroff
            ;;
        4)
            return
            ;;
    esac
}

power_menu

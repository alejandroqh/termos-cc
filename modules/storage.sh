# Storage Management Module
# Disk overview, mounts, USB devices, SMART status

source "$MODULES_DIR/common.sh"

# ============================================================================
# Disk Information
# ============================================================================

get_disk_overview() {
    if has_tool lsblk; then
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL 2>/dev/null | grep -v "loop"
    else
        df -h 2>/dev/null
    fi
}

get_disk_usage_bars() {
    local output=""
    while IFS= read -r line; do
        local mount=$(echo "$line" | awk '{print $6}')
        local used=$(echo "$line" | awk '{print $3}')
        local total=$(echo "$line" | awk '{print $2}')
        local percent=$(echo "$line" | awk '{gsub(/%/,""); print $5}')

        [ -z "$percent" ] && continue
        [ "$mount" = "Mounted" ] && continue  # Skip header

        local bar=$(make_bar "$percent" 20)
        output="$output$mount: $used / $total\n  $bar\n\n"
    done <<< "$(df -h 2>/dev/null | grep -E "^/dev" | grep -v "loop")"

    echo -e "$output"
}

show_disk_overview() {
    local info=$(get_disk_overview)

    dialog --backtitle "$BACKTITLE" \
        --title "[ Disk Overview ]" \
        --msgbox "$info" 20 75
}

show_disk_usage() {
    local bars=$(get_disk_usage_bars)

    dialog --backtitle "$BACKTITLE" \
        --title "[ Disk Usage ]" \
        --msgbox "$bars" 20 60
}

# ============================================================================
# Mount Operations
# ============================================================================

get_mounted_filesystems() {
    df -h 2>/dev/null | grep -E "^/dev" | grep -v "loop" | awk '{print $1 " on " $6 " (" $5 " used)"}'
}

get_unmounted_devices() {
    if has_tool lsblk; then
        lsblk -rno NAME,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null | \
            awk '$2=="part" && $4=="" && $3!="" {print "/dev/" $1 " (" $3 ")"}'
    fi
}

mount_device() {
    local device="$1"

    if has_tool udisksctl; then
        show_info "Mounting $device..."
        local result=$(udisksctl mount -b "$device" 2>&1)
        show_message "$result" "Mount"
    else
        show_sudo_command "mount $device /mnt" "Mounting device"
    fi
}

unmount_device() {
    local device="$1"

    if has_tool udisksctl; then
        show_info "Unmounting $device..."
        local result=$(udisksctl unmount -b "$device" 2>&1)
        show_message "$result" "Unmount"
    else
        show_sudo_command "umount $device" "Unmounting device"
    fi
}

mounted_menu() {
    while true; do
        local mounts=$(get_mounted_filesystems)

        if [ -z "$mounts" ]; then
            show_message "No mounted filesystems found." "Info"
            return
        fi

        local menu_items=""
        local i=1
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local dev=$(echo "$line" | awk '{print $1}')
            menu_items="$menu_items $i \"$line\" "
            eval "mount_$i=\"$dev\""
            i=$((i + 1))
        done <<< "$mounts"

        choice=$(eval "dialog --backtitle '$BACKTITLE' \
            --title '[ Mounted Filesystems ]' \
            --menu 'Select to unmount:' 18 70 10 $menu_items" 2>&1 >/dev/tty)

        [ -z "$choice" ] && return

        eval "selected=\$mount_$choice"

        # Don't allow unmounting critical mounts
        case "$selected" in
            /dev/sda1|/dev/nvme*n1p1|/dev/mmcblk*p1)
                if df "$selected" 2>/dev/null | grep -qE "\s+/$"; then
                    show_message "Cannot unmount root filesystem!" "Error"
                    continue
                fi
                ;;
        esac

        if confirm "Unmount $selected?"; then
            unmount_device "$selected"
        fi
    done
}

unmounted_menu() {
    while true; do
        local devices=$(get_unmounted_devices)

        if [ -z "$devices" ]; then
            show_message "No unmounted devices with filesystems found." "Info"
            return
        fi

        local menu_items=""
        local i=1
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local dev=$(echo "$line" | awk '{print $1}')
            menu_items="$menu_items $i \"$line\" "
            eval "unmount_$i=\"$dev\""
            i=$((i + 1))
        done <<< "$devices"

        choice=$(eval "dialog --backtitle '$BACKTITLE' \
            --title '[ Available Devices ]' \
            --menu 'Select to mount:' 15 60 8 $menu_items" 2>&1 >/dev/tty)

        [ -z "$choice" ] && return

        eval "selected=\$unmount_$choice"

        if confirm "Mount $selected?"; then
            mount_device "$selected"
        fi
    done
}

# ============================================================================
# USB Devices
# ============================================================================

get_usb_storage() {
    if has_tool lsblk; then
        lsblk -rno NAME,TRAN,TYPE,SIZE,MOUNTPOINT 2>/dev/null | \
            awk '$2=="usb" && $3=="disk" {print "/dev/" $1 " (" $4 ")"}'
    fi
}

get_usb_partitions() {
    local usb_disks=$(lsblk -rno NAME,TRAN 2>/dev/null | awk '$2=="usb" {print $1}')

    for disk in $usb_disks; do
        lsblk -rno NAME,TYPE,SIZE,MOUNTPOINT "/dev/$disk" 2>/dev/null | \
            awk '$2=="part" {
                if ($4 != "") {
                    print "/dev/" $1 " (" $3 ") [Mounted: " $4 "]"
                } else {
                    print "/dev/" $1 " (" $3 ") [Not mounted]"
                }
            }'
    done
}

safely_remove_usb() {
    local device="$1"

    show_info "Syncing data..."
    sync

    # Get all partitions of the device
    local partitions=$(lsblk -rno NAME "$device" 2>/dev/null | tail -n +2)

    # Unmount all partitions
    for part in $partitions; do
        local mount_point=$(lsblk -rno MOUNTPOINT "/dev/$part" 2>/dev/null)
        if [ -n "$mount_point" ]; then
            show_info "Unmounting /dev/$part..."
            if has_tool udisksctl; then
                udisksctl unmount -b "/dev/$part" 2>/dev/null
            else
                umount "/dev/$part" 2>/dev/null
            fi
        fi
    done

    # Power off the device
    if has_tool udisksctl; then
        show_info "Powering off $device..."
        local result=$(udisksctl power-off -b "$device" 2>&1)
        if [ $? -eq 0 ]; then
            show_message "Device safely removed.\nYou can now unplug it." "Success"
        else
            show_message "Could not power off device:\n$result" "Warning"
        fi
    else
        show_message "Device unmounted.\nYou may now safely remove it." "Info"
    fi
}

usb_menu() {
    while true; do
        local usb_devices=$(get_usb_storage)

        if [ -z "$usb_devices" ]; then
            show_message "No USB storage devices found." "Info"
            return
        fi

        local menu_items=""
        local i=1
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            local dev=$(echo "$line" | awk '{print $1}')
            menu_items="$menu_items $i \"$line\" "
            eval "usb_$i=\"$dev\""
            i=$((i + 1))
        done <<< "$usb_devices"

        choice=$(eval "dialog --backtitle '$BACKTITLE' \
            --title '[ USB Devices ]' \
            --menu 'Select device to safely remove:' 15 60 8 $menu_items" 2>&1 >/dev/tty)

        [ -z "$choice" ] && return

        eval "selected=\$usb_$choice"

        if confirm "Safely remove $selected?\n\nThis will unmount all partitions and power off the device."; then
            safely_remove_usb "$selected"
        fi
    done
}

# ============================================================================
# SMART Status
# ============================================================================

get_smart_status() {
    local device="$1"

    if ! has_tool smartctl; then
        return 1
    fi

    smartctl -H "$device" 2>/dev/null | grep -E "SMART overall-health|result:"
}

get_smart_info() {
    local device="$1"

    if ! has_tool smartctl; then
        return 1
    fi

    smartctl -a "$device" 2>&1
}

smart_menu() {
    if ! has_tool smartctl; then
        show_message "smartmontools not installed.\n\nInstall with:\n  sudo apk add smartmontools" "Missing Tool"
        return
    fi

    while true; do
        # Get all physical disks
        local disks=$(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk" {print "/dev/" $1}')

        if [ -z "$disks" ]; then
            show_message "No disks found." "Info"
            return
        fi

        local menu_items=""
        local i=1
        while IFS= read -r disk; do
            [ -z "$disk" ] && continue
            local status=$(get_smart_status "$disk" 2>/dev/null | grep -oE "PASSED|FAILED|Unknown" | head -1)
            [ -z "$status" ] && status="N/A"
            local size=$(lsblk -dno SIZE "$disk" 2>/dev/null)
            menu_items="$menu_items $i \"$disk ($size) [$status]\" "
            eval "disk_$i=\"$disk\""
            i=$((i + 1))
        done <<< "$disks"

        choice=$(eval "dialog --backtitle '$BACKTITLE' \
            --title '[ SMART Health ]' \
            --menu 'Select disk for details:' 15 60 8 $menu_items" 2>&1 >/dev/tty)

        [ -z "$choice" ] && return

        eval "selected=\$disk_$choice"

        # Show SMART info
        show_info "Reading SMART data..."
        local info=$(get_smart_info "$selected")

        # Show in scrollable dialog
        dialog --backtitle "$BACKTITLE" \
            --title "[ SMART Info: $selected ]" \
            --msgbox "$info" 22 75
    done
}

# ============================================================================
# Main Storage Menu
# ============================================================================

storage_menu() {
    while true; do
        choice=$(dialog --backtitle "$BACKTITLE" \
            --title "[ Storage Management ]" \
            --menu "Select option:" 16 55 7 \
            1 "Disk Overview" \
            2 "Disk Usage (with bars)" \
            3 "Mounted Filesystems" \
            4 "Mount Device" \
            5 "USB Devices" \
            6 "Disk Health (SMART)" \
            2>&1 >/dev/tty)

        local exit_status=$?
        [ $exit_status -ne 0 ] && return

        case $choice in
            1) show_disk_overview ;;
            2) show_disk_usage ;;
            3) mounted_menu ;;
            4) unmounted_menu ;;
            5) usb_menu ;;
            6) smart_menu ;;
        esac
    done
}

storage_menu

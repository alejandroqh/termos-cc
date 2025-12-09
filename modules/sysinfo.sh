# System Info Module - Enhanced
# System information, sensors, GPU, real-time monitoring

source "$MODULES_DIR/common.sh"

# ============================================================================
# Basic System Info
# ============================================================================

get_os() {
    . /etc/os-release 2>/dev/null
    echo "${PRETTY_NAME:-Unknown OS}"
}

get_kernel() {
    uname -r
}

get_hostname() {
    hostname
}

get_cpu() {
    lscpu 2>/dev/null | grep "Model name:" | cut -d':' -f2 | xargs
}

get_memory() {
    local percent=$(get_memory_percent)
    local info=$(get_memory_info)
    echo "$info (${percent}%)"
}

get_disk() {
    local percent=$(get_disk_percent)
    local info=$(get_disk_info)
    echo "$info (${percent}%)"
}

get_battery() {
    get_battery_info
}

get_uptime() {
    uptime | sed 's/.*up //' | sed 's/,.*user.*//' | xargs
}

get_load() {
    uptime | sed 's/.*load average: //'
}

# ============================================================================
# Temperature Sensors
# ============================================================================

get_cpu_temp() {
    # Try different sources for CPU temperature
    local temp=""

    # Try hwmon (most common)
    for hwmon in /sys/class/hwmon/hwmon*/temp*_input; do
        if [ -f "$hwmon" ]; then
            local label_file="${hwmon%_input}_label"
            if [ -f "$label_file" ] && grep -qi "core\|cpu\|package" "$label_file" 2>/dev/null; then
                temp=$(cat "$hwmon" 2>/dev/null)
                [ -n "$temp" ] && echo "$((temp / 1000))°C" && return
            fi
        fi
    done

    # Try thermal zones
    for zone in /sys/class/thermal/thermal_zone*/temp; do
        if [ -f "$zone" ]; then
            temp=$(cat "$zone" 2>/dev/null)
            [ -n "$temp" ] && echo "$((temp / 1000))°C" && return
        fi
    done

    # Try lm_sensors
    if has_tool sensors; then
        temp=$(sensors 2>/dev/null | grep -iE "core 0|cpu|package" | head -1 | grep -oE "[0-9]+\.[0-9]+°C" | head -1)
        [ -n "$temp" ] && echo "$temp" && return
    fi

    echo "N/A"
}

get_all_temps() {
    if has_tool sensors; then
        sensors 2>/dev/null
    else
        local output=""
        for zone in /sys/class/thermal/thermal_zone*/temp; do
            if [ -f "$zone" ]; then
                local zone_dir=$(dirname "$zone")
                local type=$(cat "$zone_dir/type" 2>/dev/null)
                local temp=$(cat "$zone" 2>/dev/null)
                [ -n "$temp" ] && output="$output$type: $((temp / 1000))°C\n"
            fi
        done
        echo -e "$output"
    fi
}

get_fan_speeds() {
    if has_tool sensors; then
        sensors 2>/dev/null | grep -i "fan" | head -5
    else
        echo "N/A (install lm_sensors)"
    fi
}

show_sensors() {
    local temps=$(get_all_temps)
    local fans=$(get_fan_speeds)

    local info="=== Temperatures ===\n$temps\n\n=== Fan Speeds ===\n$fans"

    dialog --backtitle "$BACKTITLE" \
        --title "[ Sensors ]" \
        --msgbox "$info" 22 70
}

# ============================================================================
# GPU Information
# ============================================================================

get_gpu_info() {
    local gpu=""

    # Try lspci
    if has_tool lspci; then
        gpu=$(lspci 2>/dev/null | grep -iE "vga|3d|display" | cut -d':' -f3 | head -3)
    fi

    if [ -z "$gpu" ]; then
        gpu="No GPU detected"
    fi

    echo "$gpu"
}

get_gpu_driver() {
    # Check for loaded GPU kernel modules
    local drivers=""

    for drv in i915 amdgpu radeon nouveau nvidia; do
        if lsmod 2>/dev/null | grep -q "^$drv "; then
            drivers="$drivers $drv"
        fi
    done

    echo "${drivers:-Unknown}"
}

show_gpu_info() {
    local gpu=$(get_gpu_info)
    local driver=$(get_gpu_driver)

    local info="=== GPU ===\n$gpu\n\n=== Driver ===\n$driver"

    # Add nvidia-smi info if available
    if has_tool nvidia-smi; then
        local nvidia_info=$(nvidia-smi --query-gpu=name,temperature.gpu,memory.used,memory.total --format=csv,noheader 2>/dev/null)
        info="$info\n\n=== NVIDIA Info ===\n$nvidia_info"
    fi

    dialog --backtitle "$BACKTITLE" \
        --title "[ GPU Information ]" \
        --msgbox "$info" 18 70
}

# ============================================================================
# Hardware Details
# ============================================================================

show_pci_devices() {
    if ! has_tool lspci; then
        show_message "lspci not available.\n\nInstall with:\n  sudo apk add pciutils" "Error"
        return
    fi

    local devices=$(lspci 2>/dev/null)

    dialog --backtitle "$BACKTITLE" \
        --title "[ PCI Devices ]" \
        --msgbox "$devices" 22 80
}

show_usb_devices() {
    if ! has_tool lsusb; then
        show_message "lsusb not available.\n\nInstall with:\n  sudo apk add usbutils" "Error"
        return
    fi

    local devices=$(lsusb 2>/dev/null)

    dialog --backtitle "$BACKTITLE" \
        --title "[ USB Devices ]" \
        --msgbox "$devices" 18 70
}

# ============================================================================
# Network Stats
# ============================================================================

get_network_stats() {
    local output=""

    for iface in /sys/class/net/*; do
        local name=$(basename "$iface")
        [ "$name" = "lo" ] && continue

        local rx_bytes=$(cat "$iface/statistics/rx_bytes" 2>/dev/null)
        local tx_bytes=$(cat "$iface/statistics/tx_bytes" 2>/dev/null)

        if [ -n "$rx_bytes" ] && [ -n "$tx_bytes" ]; then
            local rx_mb=$((rx_bytes / 1024 / 1024))
            local tx_mb=$((tx_bytes / 1024 / 1024))
            output="$output$name: RX ${rx_mb}MB / TX ${tx_mb}MB\n"
        fi
    done

    echo -e "$output"
}

show_network_stats() {
    local stats=$(get_network_stats)

    dialog --backtitle "$BACKTITLE" \
        --title "[ Network Statistics ]" \
        --msgbox "Bytes transferred since boot:\n\n$stats" 15 50
}

# ============================================================================
# Real-time Monitor
# ============================================================================

realtime_monitor() {
    while true; do
        local cpu_temp=$(get_cpu_temp)
        local load=$(get_load)
        local mem_percent=$(get_memory_percent)
        local mem_bar=$(make_bar "$mem_percent" 25)
        local disk_percent=$(get_disk_percent)
        local disk_bar=$(make_bar "$disk_percent" 25)
        local battery=$(get_battery)

        local info="
            REAL-TIME MONITOR

  CPU Temp:   $cpu_temp
  Load Avg:   $load

  Memory:     $mem_bar
  Disk (/):   $disk_bar

  Battery:    $battery


Auto-refreshing every 2 seconds...
Press any key to return."

        dialog --backtitle "$BACKTITLE" \
            --title "[ Real-time Monitor ]" \
            --timeout 2 \
            --infobox "$info" 18 50

        # Check if user pressed a key
        read -t 2 -n 1 && return
    done
}

# ============================================================================
# Original Menus (Enhanced)
# ============================================================================

show_overview() {
    local cpu_temp=$(get_cpu_temp)

    info="System:    $(get_os)
Kernel:    $(get_kernel)
Host:      $(get_hostname)
CPU:       $(get_cpu)
CPU Temp:  $cpu_temp
Memory:    $(get_memory)
Disk (/):  $(get_disk)
Battery:   $(get_battery)
Uptime:    $(get_uptime)
Load:      $(get_load)"

    dialog --backtitle "$BACKTITLE" \
        --title "[ Quick Overview ]" \
        --msgbox "$info" 16 65
}

show_cpu() {
    info=$(lscpu 2>/dev/null | grep -E "Model name|Architecture|CPU\(s\)|Thread|Core|MHz|Cache")

    dialog --backtitle "$BACKTITLE" \
        --title "[ CPU Details ]" \
        --msgbox "$info" 18 70
}

show_memory() {
    local percent=$(get_memory_percent)
    local used=$(free -h | awk '/^Mem:/ {print $3}')
    local total=$(free -h | awk '/^Mem:/ {print $2}')
    local bar=$(make_bar "$percent" 30)

    # Add swap info
    local swap=$(free -h | awk '/^Swap:/ {printf "%s / %s", $3, $2}')

    dialog --backtitle "$BACKTITLE" \
        --title "[ Memory Usage ]" \
        --msgbox "RAM: $used / $total\n\n$bar\n\nSwap: $swap" 11 50
}

show_disk() {
    local percent=$(get_disk_percent)
    local info=$(df -h | grep -E "^/dev|^Filesystem")
    local bar=$(make_bar "$percent" 30)

    dialog --backtitle "$BACKTITLE" \
        --title "[ Disk Usage ]" \
        --msgbox "Root partition:\n$bar\n\nAll filesystems:\n$info" 18 75
}

# ============================================================================
# Main Menu
# ============================================================================

sysinfo_menu() {
    while true; do
        choice=$(dialog --backtitle "$BACKTITLE" \
            --title "[ System Information ]" \
            --menu "Select info to view:" 22 55 13 \
            1 "Quick Overview" \
            2 "Real-time Monitor" \
            3 "CPU Details" \
            4 "Memory Usage" \
            5 "Disk Usage" \
            6 "Sensors (Temps & Fans)" \
            7 "GPU Information" \
            8 "PCI Devices" \
            9 "USB Devices" \
            10 "Network Stats" \
            11 "Open fastfetch" \
            12 "Open btop" \
            13 "Open htop" \
            2>&1 >/dev/tty)

        exit_status=$?
        [ $exit_status -ne 0 ] && return

        case $choice in
            1) show_overview ;;
            2) realtime_monitor ;;
            3) show_cpu ;;
            4) show_memory ;;
            5) show_disk ;;
            6) show_sensors ;;
            7) show_gpu_info ;;
            8) show_pci_devices ;;
            9) show_usb_devices ;;
            10) show_network_stats ;;
            11) clear; fastfetch 2>/dev/null || echo "fastfetch not installed"; read -n 1 -s -r -p "Press any key to continue..." ;;
            12) clear; btop 2>/dev/null || echo "btop not installed"; read -n 1 -s -r -p "Press any key to continue..." ;;
            13) clear; htop 2>/dev/null || echo "htop not installed"; read -n 1 -s -r -p "Press any key to continue..." ;;
        esac
    done
}

sysinfo_menu

# Network Settings Module
# VPN, WireGuard, DNS, and Network Diagnostics

source "$MODULES_DIR/common.sh"

# ============================================================================
# VPN Functions (NetworkManager)
# ============================================================================

get_vpn_connections() {
    if ! has_tool nmcli; then
        return 1
    fi
    nmcli -t -f name,type connection show 2>/dev/null | grep -E ":vpn$|:wireguard$" | cut -d':' -f1
}

get_active_vpn() {
    if ! has_tool nmcli; then
        return 1
    fi
    nmcli -t -f name,type connection show --active 2>/dev/null | grep -E ":vpn$|:wireguard$" | cut -d':' -f1
}

connect_vpn() {
    local name="$1"
    show_info "Connecting to $name..."
    nmcli connection up "$name" 2>&1
    if [ $? -eq 0 ]; then
        show_message "Connected to $name" "VPN"
    else
        show_message "Failed to connect to $name" "Error"
    fi
}

disconnect_vpn() {
    local name="$1"
    nmcli connection down "$name" 2>/dev/null
    show_info "Disconnected from $name"
}

vpn_menu() {
    if ! require_tool nmcli "NetworkManager CLI"; then
        return
    fi

    while true; do
        local connections=$(get_vpn_connections)
        local active=$(get_active_vpn)

        if [ -z "$connections" ]; then
            show_message "No VPN connections configured.\n\nAdd VPN connections via:\n  nmcli connection import type openvpn file <config.ovpn>\n  nmcli connection import type wireguard file <config.conf>" "No VPNs"
            return
        fi

        # Prepare menu data in "conn:display" format
        local menu_data=""
        while IFS= read -r conn; do
            [ -z "$conn" ] && continue
            if echo "$active" | grep -qx "$conn"; then
                menu_data="${menu_data}${conn}:${conn} [ACTIVE]\n"
            else
                menu_data="${menu_data}${conn}:${conn}\n"
            fi
        done <<< "$connections"

        local selected
        selected=$(build_dynamic_menu "VPN Connections" "Select VPN:" "$menu_data" ":" 15 50)
        [ $? -ne 0 ] && return

        # Check if active
        if echo "$active" | grep -qx "$selected"; then
            if confirm "Disconnect from $selected?"; then
                disconnect_vpn "$selected"
            fi
        else
            if confirm "Connect to $selected?"; then
                connect_vpn "$selected"
            fi
        fi
    done
}

# ============================================================================
# WireGuard Functions
# ============================================================================

get_wg_interfaces() {
    if has_tool wg; then
        wg show interfaces 2>/dev/null
    fi
}

get_wg_status() {
    local interface="$1"
    if wg show "$interface" 2>/dev/null | grep -q "interface"; then
        echo "UP"
    else
        echo "DOWN"
    fi
}

wg_toggle() {
    local interface="$1"
    local status=$(get_wg_status "$interface")

    if [ "$status" = "UP" ]; then
        show_sudo_command "wg-quick down $interface" "Bringing down WireGuard"
    else
        show_sudo_command "wg-quick up $interface" "Bringing up WireGuard"
    fi
}

wireguard_menu() {
    if ! has_tool wg; then
        show_message "WireGuard tools not installed.\n\nInstall with:\n  sudo apk add wireguard-tools" "Missing Tool"
        return
    fi

    while true; do
        local interfaces=$(get_wg_interfaces)
        local configs=$(ls /etc/wireguard/*.conf 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/.conf$//')

        # Combine active interfaces and config files
        local all_interfaces=$(echo -e "$interfaces\n$configs" | sort -u | grep -v "^$")

        if [ -z "$all_interfaces" ]; then
            show_message "No WireGuard interfaces found.\n\nAdd config files to /etc/wireguard/" "No Interfaces"
            return
        fi

        # Prepare menu data in "iface:display" format
        local menu_data=""
        while IFS= read -r iface; do
            [ -z "$iface" ] && continue
            local status=$(get_wg_status "$iface")
            menu_data="${menu_data}${iface}:${iface} [${status}]\n"
        done <<< "$all_interfaces"

        local selected
        selected=$(build_dynamic_menu "WireGuard" "Select interface to toggle:" "$menu_data" ":" 15 50)
        [ $? -ne 0 ] && return
        wg_toggle "$selected"
    done
}

# ============================================================================
# DNS Functions
# ============================================================================

get_current_dns() {
    if has_tool resolvectl; then
        resolvectl dns 2>/dev/null | head -5
    elif [ -f /etc/resolv.conf ]; then
        grep "^nameserver" /etc/resolv.conf | awk '{print $2}'
    else
        echo "Unknown"
    fi
}

show_dns_info() {
    local dns=$(get_current_dns)
    dialog --backtitle "$BACKTITLE" \
        --title "[ Current DNS ]" \
        --msgbox "Current DNS Servers:\n\n$dns" 12 50
}

set_dns_preset() {
    local dns1="$1"
    local dns2="$2"
    local name="$3"

    show_message "To set DNS to $name:\n\n1. Edit /etc/resolv.conf:\n   nameserver $dns1\n   nameserver $dns2\n\nOr use NetworkManager:\n   nmcli con mod <connection> ipv4.dns \"$dns1 $dns2\"\n   nmcli con mod <connection> ipv4.ignore-auto-dns yes" "Set DNS"
}

dns_menu() {
    while true; do
        choice=$(dialog --backtitle "$BACKTITLE" \
            --title "[ DNS Settings ]" \
            --menu "Select option:" 16 55 7 \
            1 "Show Current DNS" \
            2 "Use Cloudflare (1.1.1.1)" \
            3 "Use Google (8.8.8.8)" \
            4 "Use Quad9 (9.9.9.9)" \
            5 "Use OpenDNS (208.67.222.222)" \
            6 "Use Cloudflare Family (1.1.1.3)" \
            7 "Custom DNS" \
            2>&1 >/dev/tty)

        local exit_status=$?
        [ $exit_status -ne 0 ] && return

        case $choice in
            1) show_dns_info ;;
            2) set_dns_preset "1.1.1.1" "1.0.0.1" "Cloudflare" ;;
            3) set_dns_preset "8.8.8.8" "8.8.4.4" "Google" ;;
            4) set_dns_preset "9.9.9.9" "149.112.112.112" "Quad9" ;;
            5) set_dns_preset "208.67.222.222" "208.67.220.220" "OpenDNS" ;;
            6) set_dns_preset "1.1.1.3" "1.0.0.3" "Cloudflare Family" ;;
            7)
                local custom=$(get_input "Enter primary DNS server:" "Custom DNS")
                [ -n "$custom" ] && set_dns_preset "$custom" "$custom" "Custom"
                ;;
        esac
    done
}

# ============================================================================
# Network Diagnostics
# ============================================================================

get_gateway() {
    ip route | grep default | awk '{print $3}' | head -1
}

ping_test() {
    local target="$1"
    local name="$2"

    show_info "Pinging $name..."

    local result=$(ping -c 3 -W 2 "$target" 2>&1)
    local status=$?

    if [ $status -eq 0 ]; then
        local stats=$(echo "$result" | tail -2)
        dialog --backtitle "$BACKTITLE" \
            --title "[ Ping $name ]" \
            --msgbox "Success!\n\n$stats" 10 60
    else
        dialog --backtitle "$BACKTITLE" \
            --title "[ Ping $name ]" \
            --msgbox "Failed!\n\n$result" 12 60
    fi
}

traceroute_test() {
    local target="$1"

    if ! has_tool traceroute; then
        show_message "traceroute not installed.\n\nInstall with:\n  sudo apk add traceroute" "Missing Tool"
        return
    fi

    dialog --backtitle "$BACKTITLE" \
        --title "[ Traceroute to $target ]" \
        --infobox "Running traceroute (max 15 hops)...\nThis may take a moment." 5 45

    local result=$(traceroute -m 15 -w 2 "$target" 2>&1)

    dialog --backtitle "$BACKTITLE" \
        --title "[ Traceroute to $target ]" \
        --msgbox "$result" 20 70
}

show_interfaces() {
    local info=""

    if has_tool ip; then
        info=$(ip -br addr 2>/dev/null)
    elif has_tool ifconfig; then
        info=$(ifconfig 2>/dev/null | grep -E "^[a-z]|inet ")
    fi

    dialog --backtitle "$BACKTITLE" \
        --title "[ Network Interfaces ]" \
        --msgbox "$info" 18 70
}

show_routes() {
    local routes=$(ip route 2>/dev/null)

    dialog --backtitle "$BACKTITLE" \
        --title "[ Routing Table ]" \
        --msgbox "$routes" 15 70
}

speed_test() {
    if ! has_tool speedtest-cli; then
        show_message "speedtest-cli not installed.\n\nInstall with:\n  pip install speedtest-cli\n  or\n  sudo apk add speedtest-cli" "Missing Tool"
        return
    fi

    dialog --backtitle "$BACKTITLE" \
        --title "[ Speed Test ]" \
        --infobox "Running speed test...\nThis may take 30-60 seconds." 5 45

    local result=$(speedtest-cli --simple 2>&1)

    dialog --backtitle "$BACKTITLE" \
        --title "[ Speed Test Results ]" \
        --msgbox "$result" 10 50
}

diagnostics_menu() {
    while true; do
        local gateway=$(get_gateway)

        choice=$(dialog --backtitle "$BACKTITLE" \
            --title "[ Network Diagnostics ]" \
            --menu "Select test:" 16 55 8 \
            1 "Ping Gateway ($gateway)" \
            2 "Ping Internet (8.8.8.8)" \
            3 "Ping Cloudflare (1.1.1.1)" \
            4 "Traceroute to Google" \
            5 "Show Interfaces" \
            6 "Show Routes" \
            7 "Speed Test" \
            8 "Custom Ping" \
            2>&1 >/dev/tty)

        local exit_status=$?
        [ $exit_status -ne 0 ] && return

        case $choice in
            1) ping_test "$gateway" "Gateway" ;;
            2) ping_test "8.8.8.8" "Google DNS" ;;
            3) ping_test "1.1.1.1" "Cloudflare" ;;
            4) traceroute_test "google.com" ;;
            5) show_interfaces ;;
            6) show_routes ;;
            7) speed_test ;;
            8)
                local target=$(get_input "Enter hostname or IP:" "Ping")
                [ -n "$target" ] && ping_test "$target" "$target"
                ;;
        esac
    done
}

# ============================================================================
# Main Network Menu
# ============================================================================

network_menu() {
    while true; do
        local active_vpn=$(get_active_vpn)
        local vpn_status="None"
        [ -n "$active_vpn" ] && vpn_status="$active_vpn"

        choice=$(dialog --backtitle "$BACKTITLE" \
            --title "[ Network Settings ]" \
            --menu "Active VPN: $vpn_status" 15 55 6 \
            1 "VPN Connections" \
            2 "WireGuard" \
            3 "DNS Settings" \
            4 "Network Diagnostics" \
            5 "Open nmtui" \
            2>&1 >/dev/tty)

        local exit_status=$?
        [ $exit_status -ne 0 ] && return

        case $choice in
            1) vpn_menu ;;
            2) wireguard_menu ;;
            3) dns_menu ;;
            4) diagnostics_menu ;;
            5) clear; nmtui 2>/dev/null || show_message "nmtui not available" "Error" ;;
        esac
    done
}

network_menu

# System Updates Module
# Alpine Linux package management (apk)

source "$MODULES_DIR/common.sh"

# ============================================================================
# Update Check
# ============================================================================

check_updates() {
    if ! has_tool apk; then
        show_message "apk package manager not found.\nThis module is for Alpine Linux." "Error"
        return 1
    fi

    show_info "Checking for updates..."

    # Update package index (may need sudo for writing to cache)
    apk update 2>/dev/null

    # Get upgradeable packages
    local updates=$(apk version -l '<' 2>/dev/null | grep -v "Installed:")

    if [ -z "$updates" ]; then
        show_message "System is up to date!\nNo packages need updating." "Updates"
        return 0
    fi

    local count=$(echo "$updates" | wc -l)

    dialog --backtitle "$BACKTITLE" \
        --title "[ Available Updates: $count ]" \
        --msgbox "$updates" 20 70
}

update_system() {
    show_sudo_command "apk upgrade" "System update"
}

# ============================================================================
# Package Search
# ============================================================================

search_packages() {
    local query=$(get_input "Enter package name to search:" "Search")
    [ -z "$query" ] && return

    show_info "Searching for '$query'..."

    local results=$(apk search -v "$query" 2>/dev/null | head -50)

    if [ -z "$results" ]; then
        show_message "No packages found matching '$query'" "Search"
        return
    fi

    dialog --backtitle "$BACKTITLE" \
        --title "[ Search Results ]" \
        --msgbox "$results" 20 70
}

# ============================================================================
# Installed Packages
# ============================================================================

list_installed() {
    show_info "Loading installed packages..."

    local packages=$(apk list -I 2>/dev/null | head -100)
    local total=$(apk list -I 2>/dev/null | wc -l)

    dialog --backtitle "$BACKTITLE" \
        --title "[ Installed Packages ($total total, showing first 100) ]" \
        --msgbox "$packages" 22 75
}

# ============================================================================
# Package Info
# ============================================================================

package_info() {
    local package=$(get_input "Enter package name:" "Package Info")
    [ -z "$package" ] && return

    show_info "Getting info for '$package'..."

    local info=$(apk info -a "$package" 2>&1)

    if echo "$info" | grep -q "No such package"; then
        show_message "Package '$package' not found.\n\nTry searching for it first." "Error"
        return
    fi

    dialog --backtitle "$BACKTITLE" \
        --title "[ Package: $package ]" \
        --msgbox "$info" 22 75
}

# ============================================================================
# Package Operations
# ============================================================================

install_package() {
    local package=$(get_input "Enter package name to install:" "Install")
    [ -z "$package" ] && return

    # Verify package exists
    if ! apk search -x "$package" 2>/dev/null | grep -q "^$package$"; then
        show_message "Package '$package' not found in repositories." "Error"
        return
    fi

    show_sudo_command "apk add $package" "Installing $package"
}

remove_package() {
    local package=$(get_input "Enter package name to remove:" "Remove")
    [ -z "$package" ] && return

    # Verify package is installed
    if ! apk list -I 2>/dev/null | grep -q "^$package "; then
        show_message "Package '$package' is not installed." "Error"
        return
    fi

    if confirm "Remove package '$package'?\n\nThis may also remove dependent packages."; then
        show_sudo_command "apk del $package" "Removing $package"
    fi
}

# ============================================================================
# Repository Info
# ============================================================================

show_repositories() {
    local repos=""

    if [ -f /etc/apk/repositories ]; then
        repos=$(cat /etc/apk/repositories 2>/dev/null)
    else
        repos="Repository file not found"
    fi

    dialog --backtitle "$BACKTITLE" \
        --title "[ Repositories ]" \
        --msgbox "Configured repositories:\n\n$repos" 15 70
}

# ============================================================================
# Cache Management
# ============================================================================

cache_info() {
    local cache_dir="/var/cache/apk"
    local cache_size="N/A"

    if [ -d "$cache_dir" ]; then
        cache_size=$(du -sh "$cache_dir" 2>/dev/null | cut -f1)
    fi

    dialog --backtitle "$BACKTITLE" \
        --title "[ Cache Info ]" \
        --msgbox "Cache directory: $cache_dir\nCache size: $cache_size\n\nTo clear cache, run:\n  sudo apk cache clean" 12 55
}

# ============================================================================
# Quick Stats
# ============================================================================

get_package_stats() {
    local installed=$(apk list -I 2>/dev/null | wc -l)
    local available=$(apk search 2>/dev/null | wc -l)

    echo "Installed packages: $installed"
    echo "Available packages: $available"
}

# ============================================================================
# Main Updates Menu
# ============================================================================

updates_menu() {
    if ! has_tool apk; then
        show_message "This module requires Alpine Linux (apk)." "Error"
        return
    fi

    while true; do
        local stats=$(get_package_stats)

        choice=$(dialog --backtitle "$BACKTITLE" \
            --title "[ System Updates ]" \
            --menu "$stats" 18 55 9 \
            1 "Check for Updates" \
            2 "Update All Packages" \
            3 "Search Packages" \
            4 "Installed Packages" \
            5 "Package Info" \
            6 "Install Package" \
            7 "Remove Package" \
            8 "Repositories" \
            9 "Cache Info" \
            2>&1 >/dev/tty)

        local exit_status=$?
        [ $exit_status -ne 0 ] && return

        case $choice in
            1) check_updates ;;
            2) update_system ;;
            3) search_packages ;;
            4) list_installed ;;
            5) package_info ;;
            6) install_package ;;
            7) remove_package ;;
            8) show_repositories ;;
            9) cache_info ;;
        esac
    done
}

updates_menu

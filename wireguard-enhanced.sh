#!/bin/bash

# WireGuard Enhanced Installation Script
# This script serves as the main controller for the WireGuard VPN system.

# Import our core modules using absolute paths
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/wireguard-core.sh"
source "${SCRIPT_DIR}/client-config.sh"
source "${SCRIPT_DIR}/multi-tunnel.sh"
source "${SCRIPT_DIR}/batch-operations.sh"

# Configure VPN mode selection
function configure_vpn_mode() {
    echo "Select VPN Mode:"
    echo "1) Proxy Mode - Route all traffic through VPN (recommended for most users)"
    echo "2) Split Tunnel Mode - Route only specific networks"
    
    local mode_choice
    while true; do
        read -rp "Choose mode [1-2]: " mode_choice
        case $mode_choice in
            1) 
                echo "proxy"
                return 0
                ;;
            2) 
                echo "split"
                return 0
                ;;
            *) 
                echo "Invalid choice. Please select 1 or 2."
                ;;
        esac
    done
}

# Validate IP address or hostname
function validate_address() {
    local address="$1"
    
    # First, check if it's a valid IP address
    if [[ $address =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # Validate each octet
        local IFS='.'
        read -ra ADDR <<< "$address"
        for i in "${ADDR[@]}"; do
            if [[ $i -lt 0 || $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    
    # If not an IP, check if it's a valid hostname
    if [[ $address =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    fi
    
    return 1
}

function install_wireguard() {
    log_message "INFO" "Starting WireGuard installation"
    
    # Get VPN mode preference
    local vpn_mode
    vpn_mode=$(configure_vpn_mode)
    log_message "INFO" "Selected VPN mode: $vpn_mode"
    
    # Configure initial settings
    local server_address
    read -rp "Server public IP or hostname: " server_address
    
    if ! validate_address "$server_address"; then
        log_message "ERROR" "Invalid server address provided"
        return 1
    fi
    
    # Get interface name
    local interface_name
    read -rp "WireGuard interface name [wg0]: " interface_name
    interface_name=${interface_name:-wg0}
    
    if ! [[ $interface_name =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_message "ERROR" "Invalid interface name. Use only letters, numbers, underscore, and hyphen"
        return 1
    fi
    
    # Install WireGuard and dependencies
    log_message "INFO" "Installing WireGuard and dependencies..."
    if ! install_dependencies; then
        log_message "ERROR" "Failed to install dependencies"
        return 1
    fi
    
    # Generate server keys
    log_message "INFO" "Generating server keys..."
    if ! generate_keys "server"; then
        log_message "ERROR" "Failed to generate server keys"
        return 1
    fi
    
    # Create server configuration
    if ! create_server_config "$interface_name" "$server_address" "$vpn_mode"; then
        log_message "ERROR" "Failed to create server configuration"
        return 1
    fi
    
    # Configure networking
    if ! configure_networking "$interface_name"; then
        log_message "ERROR" "Failed to configure networking"
        return 1
    }
    
    log_message "SUCCESS" "WireGuard installation completed successfully"
    
    # Offer to create first client
    local create_client
    read -rp "Would you like to create your first client now? [y/N] " create_client
    if [[ ${create_client,,} == "y" ]]; then
        create_new_client
    fi
    
    return 0
}

function create_server_config() {
    local interface="$1"
    local address="$2"
    local mode="$3"
    
    local config_file="/etc/wireguard/${interface}.conf"
    local private_key
    private_key=$(cat "/etc/wireguard/keys/server/private.key")
    
    # Create basic configuration
    cat > "$config_file" << EOF
[Interface]
PrivateKey = ${private_key}
Address = 10.0.0.1/24
ListenPort = 51820

# Server configuration
SaveConfig = true

# Network configuration
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOF
    
    chmod 600 "$config_file"
    return 0
}

function configure_networking() {
    local interface="$1"
    
    # Enable IP forwarding
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-wireguard.conf
    echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.d/99-wireguard.conf
    sysctl --system
    
    # Start WireGuard service
    systemctl enable "wg-quick@${interface}"
    systemctl start "wg-quick@${interface}"
    
    # Verify service is running
    if ! systemctl is-active --quiet "wg-quick@${interface}"; then
        return 1
    fi
    
    return 0
}

# Main menu
function show_main_menu() {
    while true; do
        echo -e "\nWireGuard VPN Management System"
        echo "==============================="
        echo "1) Install WireGuard"
        echo "2) Manage Tunnels"
        echo "3) Manage Clients"
        echo "4) System Configuration"
        echo "5) Exit"
        
        local choice
        read -rp "Select an option [1-5]: " choice
        
        case $choice in
            1) install_wireguard ;;
            2) manage_tunnels ;;
            3) manage_clients ;;
            4) system_configuration ;;
            5) exit 0 ;;
            *) echo "Invalid option. Please try again." ;;
        esac
    done
}

# Initialize the environment and start the script
validate_system
show_main_menu
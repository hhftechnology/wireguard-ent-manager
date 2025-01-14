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
    local mode_choice
    while true; do
        echo "Select VPN Mode:"
        echo "1) Proxy Mode - Route all traffic through VPN (recommended for most users)"
        echo "2) Split Tunnel Mode - Route only specific networks"
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
                sleep 1
                clear
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
    fi
    
    log_message "SUCCESS" "WireGuard installation completed successfully"
    
    # Offer to create first client
    local create_client
    read -rp "Would you like to create your first client now? [y/N] " create_client
    if [[ ${create_client,,} == "y" ]]; then
        local client_name
        read -rp "Enter client name: " client_name
        # Use the existing create_client function with default values
        create_client "$client_name" "wg0" "auto" || log_message "ERROR" "Failed to create first client"
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

# Placeholder functions for menu options
function manage_tunnels() {
    while true; do
        echo -e "\nTunnel Management"
        echo "================="
        echo "1) Create new tunnel"
        echo "2) List active tunnels"
        echo "3) Remove tunnel"
        echo "4) Show tunnel status"
        echo "5) Back to main menu"
        
        local choice
        read -rp "Select an option [1-5]: " choice
        
        case $choice in
            1)
                local tunnel_name port
                read -rp "Enter tunnel name: " tunnel_name
                read -rp "Enter port number [51820]: " port
                port=${port:-51820}
                
                if [[ ! $port =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
                    log_message "ERROR" "Invalid port number"
                    continue
                fi
                
                create_tunnel "$tunnel_name" "$port" || log_message "ERROR" "Failed to create tunnel $tunnel_name"
                ;;
            2)
                list_tunnels
                read -rp "Press Enter to continue..."
                ;;
            3)
                local tunnel_name
                read -rp "Enter tunnel name to remove: " tunnel_name
                remove_tunnel "$tunnel_name" || log_message "ERROR" "Failed to remove tunnel $tunnel_name"
                ;;
            4)
                echo "Active Tunnel Status:"
                echo "===================="
                wg show all || log_message "ERROR" "Failed to show tunnel status"
                read -rp "Press Enter to continue..."
                ;;
            5)
                return 0
                ;;
            *)
                log_message "WARNING" "Invalid option selected: $choice"
                ;;
        esac
    done
}

function manage_clients() {
    while true; do
        echo -e "\nClient Management"
        echo "================="
        echo "1) Create new client"
        echo "2) List clients"
        echo "3) Remove client"
        echo "4) Generate QR code"
        echo "5) Batch operations"
        echo "6) Back to main menu"
        
        local choice
        read -rp "Select an option [1-6]: " choice
        
        case $choice in
            1)
                local client_name tunnel_name ip
                read -rp "Enter client name: " client_name
                read -rp "Enter tunnel name [wg0]: " tunnel_name
                tunnel_name=${tunnel_name:-wg0}
                read -rp "Enter IP address [auto]: " ip
                ip=${ip:-auto}
                
                create_client "$client_name" "$tunnel_name" "$ip" || log_message "ERROR" "Failed to create client $client_name"
                ;;
            2)
                local tunnel_name
                read -rp "Enter tunnel name [wg0]: " tunnel_name
                tunnel_name=${tunnel_name:-wg0}
                list_clients "$tunnel_name"
                read -rp "Press Enter to continue..."
                ;;
            3)
                local client_name tunnel_name
                read -rp "Enter client name to remove: " client_name
                read -rp "Enter tunnel name [wg0]: " tunnel_name
                tunnel_name=${tunnel_name:-wg0}
                remove_client "$client_name" "$tunnel_name" || log_message "ERROR" "Failed to remove client $client_name"
                ;;
            4)
                local client_name tunnel_name
                read -rp "Enter client name: " client_name
                read -rp "Enter tunnel name [wg0]: " tunnel_name
                tunnel_name=${tunnel_name:-wg0}
                generate_qr_code "$client_name" "$tunnel_name" || log_message "ERROR" "Failed to generate QR code for $client_name"
                ;;
            5)
                manage_batch_operations
                ;;
            6)
                return 0
                ;;
            *)
                log_message "WARNING" "Invalid option selected: $choice"
                ;;
        esac
    done
}

function manage_batch_operations() {
    while true; do
        echo -e "\nBatch Operations"
        echo "================"
        echo "1) Create batch template"
        echo "2) Process batch file"
        echo "3) Back to client management"
        
        local choice
        read -rp "Select an option [1-3]: " choice
        
        case $choice in
            1)
                create_batch_template || log_message "ERROR" "Failed to create batch template"
                ;;
            2)
                local batch_file tunnel_name
                read -rp "Enter batch file path: " batch_file
                read -rp "Enter tunnel name [wg0]: " tunnel_name
                tunnel_name=${tunnel_name:-wg0}
                process_batch_clients "$batch_file" "$tunnel_name" || log_message "ERROR" "Failed to process batch file"
                ;;
            3)
                return 0
                ;;
            *)
                log_message "WARNING" "Invalid option selected: $choice"
                ;;
        esac
    done
}

function system_configuration() {
    while true; do
        echo -e "\nSystem Configuration"
        echo "==================="
        echo "1) Configure DNS settings"
        echo "2) Configure NAT settings"
        echo "3) View system logs"
        echo "4) Backup configuration"
        echo "5) Restore configuration"
        echo "6) Back to main menu"
        
        local choice
        read -rp "Select an option [1-6]: " choice
        
        case $choice in
            1)
                configure_dns
                ;;
            2)
                configure_nat
                ;;
            3)
                view_logs
                ;;
            4)
                backup_config
                ;;
            5)
                restore_config
                ;;
            6)
                return 0
                ;;
            *)
                log_message "WARNING" "Invalid option selected: $choice"
                ;;
        esac
    done
}

function configure_dns() {
    local dns_servers
    read -rp "Enter DNS servers (comma-separated) [1.1.1.1,1.0.0.1]: " dns_servers
    dns_servers=${dns_servers:-"1.1.1.1,1.0.0.1"}
    
    if ! validate_dns_servers "$dns_servers"; then
        log_message "ERROR" "Invalid DNS server format"
        return 1
    fi
    
    # Update DNS settings in WireGuard configuration
    sed -i "s/DNS = .*/DNS = ${dns_servers}/" /etc/wireguard/*.conf
    log_message "SUCCESS" "DNS settings updated"
}

function configure_nat() {
    echo "NAT Configuration Options:"
    echo "1) Standard NAT (recommended)"
    echo "2) Full-cone NAT (gaming/voice chat)"
    echo "3) Restricted NAT"
    
    local choice
    read -rp "Select NAT type [1]: " choice
    choice=${choice:-1}
    
    case $choice in
        1)
            update_nat_rules "standard"
            ;;
        2)
            update_nat_rules "full-cone"
            ;;
        3)
            update_nat_rules "restricted"
            ;;
        *)
            log_message "ERROR" "Invalid NAT type selected"
            return 1
            ;;
    esac
}

function update_nat_rules() {
    local nat_type="$1"
    local interface
    
    # Get the primary network interface
    interface=$(ip route | grep default | awk '{print $5}' | head -n1)
    
    case $nat_type in
        "standard")
            # Standard NAT configuration
            local postup="iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $interface -j MASQUERADE"
            local postdown="iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $interface -j MASQUERADE"
            ;;
        "full-cone")
            # Full-cone NAT for gaming
            local postup="iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o $interface -j MASQUERADE; iptables -t nat -A PREROUTING -i $interface -j ACCEPT"
            local postdown="iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o $interface -j MASQUERADE; iptables -t nat -D PREROUTING -i $interface -j ACCEPT"
            ;;
        "restricted")
            # Restricted NAT
            local postup="iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -m state --state RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -A POSTROUTING -o $interface -j MASQUERADE"
            local postdown="iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -m state --state RELATED,ESTABLISHED -j ACCEPT; iptables -t nat -D POSTROUTING -o $interface -j MASQUERADE"
            ;;
    esac
    
    # Update all WireGuard configurations with new NAT rules
    for conf in /etc/wireguard/*.conf; do
        sed -i "/^PostUp/c\\PostUp = $postup" "$conf"
        sed -i "/^PostDown/c\\PostDown = $postdown" "$conf"
    done
    
    log_message "SUCCESS" "NAT rules updated to $nat_type mode"
    return 0
}

function view_logs() {
    if [[ -f "$WG_LOG_DIR/wg-core.log" ]]; then
        tail -n 50 "$WG_LOG_DIR/wg-core.log"
    else
        log_message "WARNING" "No logs found"
    fi
    read -rp "Press Enter to continue..."
}

function backup_config() {
    local backup_dir="$WG_BACKUP_DIR/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup all configuration files and keys
    cp -r /etc/wireguard/* "$backup_dir/"
    
    # Create archive
    tar -czf "$backup_dir.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
    rm -rf "$backup_dir"
    
    log_message "SUCCESS" "Backup created: $backup_dir.tar.gz"
}

function restore_config() {
    local backup_file
    read -rp "Enter backup file path: " backup_file
    
    if [[ ! -f "$backup_file" ]]; then
        log_message "ERROR" "Backup file not found"
        return 1
    fi
    
    # Stop WireGuard services
    systemctl stop wg-quick@*
    
    # Create temporary directory
    local temp_dir
    temp_dir=$(mktemp -d)
    
    # Extract backup
    tar -xzf "$backup_file" -C "$temp_dir"
    
    # Restore configuration
    cp -r "$temp_dir"/*/* /etc/wireguard/
    
    # Cleanup
    rm -rf "$temp_dir"
    
    # Restart WireGuard services
    systemctl start wg-quick@*
    
    log_message "SUCCESS" "Configuration restored from $backup_file"
}

function manage_enterprise_features() {
    # Check if enterprise features are installed
    if [[ ! -f "/usr/local/lib/wireguard/wireguard_enterprise.py" ]]; then
        echo "Enterprise features are not installed."
        echo "Would you like to install them now? (y/n)"
        read -r install_choice
        if [[ ${install_choice,,} == "y" ]]; then
            ./setup-enterprise.sh
        fi
        return
    }

    while true; do
        echo -e "\nEnterprise Management"
        echo "===================="
        echo "1) Web Interface Management"
        echo "2) Monitoring System"
        echo "3) Container Management"
        echo "4) Cloud Integration"
        echo "5) Back to main menu"
        
        local choice
        read -rp "Select an option [1-5]: " choice
        
        case $choice in
            1)
                python3 /usr/local/lib/wireguard/wireguard_enterprise.py web
                ;;
            2)
                python3 /usr/local/lib/wireguard/wireguard_enterprise.py monitor
                ;;
            3)
                python3 /usr/local/lib/wireguard/wireguard_enterprise.py container
                ;;
            4)
                python3 /usr/local/lib/wireguard/wireguard_enterprise.py cloud
                ;;
            5)
                return 0
                ;;
            *)
                log_message "WARNING" "Invalid option selected: $choice"
                ;;
        esac
    done
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
        echo "5) Enterprise Features"  # New option
        echo "6) Exit"
        
        local choice
        read -rp "Select an option [1-6]: " choice
        
        case $choice in
            1) install_wireguard || log_message "ERROR" "WireGuard installation failed" ;;
            2) manage_tunnels || log_message "ERROR" "Tunnel management failed" ;;
            3) manage_clients || log_message "ERROR" "Client management failed" ;;
            4) system_configuration || log_message "ERROR" "System configuration failed" ;;
            5) manage_enterprise_features || log_message "ERROR" "Enterprise management failed" ;;
            6) log_message "INFO" "Exiting WireGuard management system"; exit 0 ;;
            *) log_message "WARNING" "Invalid option selected: $choice" ;;
        esac
    done
}

# Cleanup function for graceful exit
function cleanup() {
    log_message "INFO" "Performing cleanup before exit"
    # Add cleanup tasks here
    exit 0
}

# Set up trap for cleanup on script exit
trap cleanup EXIT

# Initialize the environment and start the script
validate_system
show_main_menu
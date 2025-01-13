#!/bin/bash

# WireGuard Installation and Management Script
# This script serves as the main controller for the WireGuard VPN system,
# integrating multiple modules for comprehensive VPN management.

# Standard color codes for script output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Import required modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/wireguard-core.sh"
source "${SCRIPT_DIR}/client-config.sh"
source "${SCRIPT_DIR}/multi-tunnel.sh"
source "${SCRIPT_DIR}/batch-operations.sh"

# Configuration directory
WG_CONFIG_DIR="/etc/wireguard"

# Logging setup
LOG_DIR="/var/log/wireguard"
LOG_FILE="${LOG_DIR}/wireguard-manager.log"

###################
# Helper Functions
###################

function setup_logging() {
    # Create log directory if it doesn't exist
    if [[ ! -d $LOG_DIR ]]; then
        mkdir -p "$LOG_DIR"
        chmod 750 "$LOG_DIR"
    fi
    
    # Initialize log file with proper permissions
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
}

function log_message() {
    local level=$1
    local message=$2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
    
    # Display message to console if not in quiet mode
    if [[ -z $QUIET_MODE ]]; then
        case $level in
            ERROR) echo -e "${RED}Error: $message${NC}" ;;
            WARNING) echo -e "${YELLOW}Warning: $message${NC}" ;;
            INFO) echo -e "$message" ;;
            SUCCESS) echo -e "${GREEN}$message${NC}" ;;
        esac
    fi
}

function check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_message "ERROR" "This script must be run as root"
        exit 1
    fi
}

function initialize_environment() {
    # Create necessary directories
    mkdir -p "$WG_CONFIG_DIR"
    chmod 700 "$WG_CONFIG_DIR"
    
    # Initialize logging
    setup_logging
    
    # Check dependencies
    check_dependencies
}

function check_dependencies() {
    local deps=("wg" "ip" "iptables" "systemctl")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_message "ERROR" "Missing required dependencies: ${missing[*]}"
        install_dependencies
    fi
}

###################
# Menu Functions
###################

function show_main_menu() {
    while true; do
        echo -e "\n${GREEN}WireGuard VPN Management System${NC}"
        echo "================================="
        echo "1) Installation & Setup"
        echo "2) Tunnel Management"
        echo "3) Client Management"
        echo "4) System Configuration"
        echo "5) Monitoring & Maintenance"
        echo "6) Backup & Restore"
        echo "7) Exit"
        echo "================================="
        
        local choice
        read -rp "Select an option [1-7]: " choice
        
        case $choice in
            1) installation_menu ;;
            2) tunnel_management_menu ;;
            3) client_management_menu ;;
            4) system_configuration_menu ;;
            5) monitoring_menu ;;
            6) backup_menu ;;
            7) 
                log_message "INFO" "Exiting WireGuard management system"
                exit 0 
                ;;
            *) log_message "WARNING" "Invalid option selected" ;;
        esac
    done
}

function installation_menu() {
    echo -e "\n${GREEN}Installation & Setup${NC}"
    echo "1) Fresh WireGuard Installation"
    echo "2) Upgrade Existing Installation"
    echo "3) Verify Installation"
    echo "4) Back to Main Menu"
    
    local choice
    read -rp "Select an option [1-4]: " choice
    
    case $choice in
        1) install_wireguard ;;
        2) upgrade_wireguard ;;
        3) verify_installation ;;
        4) return ;;
        *) log_message "WARNING" "Invalid option selected" ;;
    esac
}

function install_wireguard() {
    log_message "INFO" "Starting WireGuard installation"
    
    # Get VPN mode preference
    local vpn_mode=$(configure_vpn_mode)
    log_message "INFO" "Selected VPN mode: $vpn_mode"
    
    # Configure initial settings
    local settings_configured=0
    configure_initial_settings || settings_configured=$?
    
    if [[ $settings_configured -eq 0 ]]; then
        # Install WireGuard packages
        install_packages || {
            log_message "ERROR" "Package installation failed"
            return 1
        }
        
        # Create initial configuration
        create_initial_config "$vpn_mode" || {
            log_message "ERROR" "Configuration creation failed"
            return 1
        }
        
        # Set up firewall rules
        configure_firewall || {
            log_message "WARNING" "Firewall configuration requires attention"
        }
        
        log_message "SUCCESS" "WireGuard installation completed successfully"
        
        # Offer to create first client
        read -rp "Would you like to create your first client now? [y/N] " create_client
        [[ ${create_client,,} == "y" ]] && create_new_client
    else
        log_message "ERROR" "Installation aborted due to configuration errors"
        return 1
    fi
}

function configure_initial_settings() {
    # Collect and validate all necessary settings
    read -rp "Server public IP or hostname: " SERVER_PUB_IP
    read -rp "WireGuard interface name [wg0]: " SERVER_WG_NIC
    SERVER_WG_NIC=${SERVER_WG_NIC:-wg0}
    
    # Validate IP/hostname
    if ! validate_address "$SERVER_PUB_IP"; then
        log_message "ERROR" "Invalid server address provided"
        return 1
    fi
    
    # Generate server keys
    SERVER_PRIV_KEY=$(wg genkey)
    SERVER_PUB_KEY=$(echo "$SERVER_PRIV_KEY" | wg pubkey)
    
    # Save configuration
    save_server_config
}

function create_new_client() {
    # Get client details
    read -rp "Enter client name: " CLIENT_NAME
    read -rp "Enter client IP (or press enter for auto-assign): " CLIENT_IP
    
    if [[ -z $CLIENT_IP ]]; then
        CLIENT_IP=$(get_next_available_ip)
    fi
    
    # Configure client settings
    configure_client "$CLIENT_NAME" || {
        log_message "ERROR" "Client configuration failed"
        return 1
    }
    
    # Generate client keys and config
    generate_client_config "$CLIENT_NAME" "$CLIENT_IP"
    
    log_message "SUCCESS" "Client $CLIENT_NAME created successfully"
    
    # Offer to display QR code
    if command -v qrencode >/dev/null 2>&1; then
        read -rp "Would you like to display the client config as QR code? [y/N] " show_qr
        [[ ${show_qr,,} == "y" ]] && display_client_qr "$CLIENT_NAME"
    fi
}

###################
# Main Execution
###################

# Check if running as root
check_root

# Initialize environment
initialize_environment

###################
# Additional Menu Functions
###################

function tunnel_management_menu() {
    while true; do
        echo -e "\n${GREEN}Tunnel Management${NC}"
        echo "1) List Active Tunnels"
        echo "2) Create New Tunnel"
        echo "3) Configure Existing Tunnel"
        echo "4) Delete Tunnel"
        echo "5) Show Tunnel Status"
        echo "6) Back to Main Menu"
        
        local choice
        read -rp "Select an option [1-6]: " choice
        
        case $choice in
            1) list_tunnels ;;
            2) create_tunnel_interactive ;;
            3) configure_tunnel_interactive ;;
            4) delete_tunnel_interactive ;;
            5) show_tunnel_status ;;
            6) return ;;
            *) log_message "WARNING" "Invalid option selected" ;;
        esac
    done
}

function create_tunnel_interactive() {
    read -rp "Enter tunnel name (e.g., wg1): " tunnel_name
    if [[ -f "${WG_CONFIG_DIR}/${tunnel_name}.conf" ]]; then
        log_message "ERROR" "Tunnel $tunnel_name already exists"
        return 1
    fi
    
    # Get port number
    local port
    while true; do
        read -rp "Enter port number (1024-65535): " port
        if [[ $port =~ ^[0-9]+$ ]] && (( port >= 1024 && port <= 65535 )); then
            break
        fi
        log_message "WARNING" "Invalid port number"
    done
    
    create_new_tunnel "$tunnel_name" "$port" || {
        log_message "ERROR" "Failed to create tunnel $tunnel_name"
        return 1
    }
    
    log_message "SUCCESS" "Tunnel $tunnel_name created successfully"
}

function client_management_menu() {
    while true; do
        echo -e "\n${GREEN}Client Management${NC}"
        echo "1) Create New Client"
        echo "2) List Clients"
        echo "3) Revoke Client"
        echo "4) Batch Create Clients"
        echo "5) Show Client Status"
        echo "6) Back to Main Menu"
        
        local choice
        read -rp "Select an option [1-6]: " choice
        
        case $choice in
            1) create_new_client ;;
            2) list_clients ;;
            3) revoke_client_interactive ;;
            4) batch_create_clients_interactive ;;
            5) show_client_status ;;
            6) return ;;
            *) log_message "WARNING" "Invalid option selected" ;;
        esac
    done
}

function system_configuration_menu() {
    while true; do
        echo -e "\n${GREEN}System Configuration${NC}"
        echo "1) Configure Firewall"
        echo "2) Configure DNS"
        echo "3) Configure NAT Settings"
        echo "4) Configure Automatic Updates"
        echo "5) Configure Logging"
        echo "6) Back to Main Menu"
        
        local choice
        read -rp "Select an option [1-6]: " choice
        
        case $choice in
            1) configure_firewall_interactive ;;
            2) configure_dns_interactive ;;
            3) configure_nat_interactive ;;
            4) configure_updates ;;
            5) configure_logging ;;
            6) return ;;
            *) log_message "WARNING" "Invalid option selected" ;;
        esac
    done
}

function monitoring_menu() {
    while true; do
        echo -e "\n${GREEN}Monitoring & Maintenance${NC}"
        echo "1) Show System Status"
        echo "2) Show Active Connections"
        echo "3) View Logs"
        echo "4) Clean Inactive Peers"
        echo "5) Performance Statistics"
        echo "6) Back to Main Menu"
        
        local choice
        read -rp "Select an option [1-6]: " choice
        
        case $choice in
            1) show_system_status ;;
            2) show_active_connections ;;
            3) view_logs ;;
            4) clean_inactive_peers ;;
            5) show_statistics ;;
            6) return ;;
            *) log_message "WARNING" "Invalid option selected" ;;
        esac
    done
}

function backup_menu() {
    while true; do
        echo -e "\n${GREEN}Backup & Restore${NC}"
        echo "1) Create Backup"
        echo "2) Restore from Backup"
        echo "3) Export Client Configs"
        echo "4) Import Client Configs"
        echo "5) Back to Main Menu"
        
        local choice
        read -rp "Select an option [1-5]: " choice
        
        case $choice in
            1) create_backup ;;
            2) restore_backup ;;
            3) export_client_configs ;;
            4) import_client_configs ;;
            5) return ;;
            *) log_message "WARNING" "Invalid option selected" ;;
        esac
    done
}

###################
# Main Execution
###################

# Check if running as root
check_root

# Initialize environment
initialize_environment

# Start the management system
log_message "INFO" "Starting WireGuard management system"
show_main_menu

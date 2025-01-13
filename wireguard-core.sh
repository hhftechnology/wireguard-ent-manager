#!/bin/bash

# WireGuard Core Module (wireguard-core.sh)
# This module provides core functionality for WireGuard VPN management

# Standard color codes for script output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Critical system paths
WG_CONFIG_DIR="/etc/wireguard"
WG_KEY_DIR="${WG_CONFIG_DIR}/keys"
WG_LOG_DIR="/var/log/wireguard"
WG_BACKUP_DIR="/var/backup/wireguard"

# Initialize directories
function init_directories() {
    local dirs=("$WG_CONFIG_DIR" "$WG_KEY_DIR" "$WG_LOG_DIR" "$WG_BACKUP_DIR")
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chmod 700 "$dir"
        fi
    done
}

# Log messages with timestamp
function log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Create log directory if it doesn't exist
    [[ ! -d "$WG_LOG_DIR" ]] && mkdir -p "$WG_LOG_DIR"
    
    echo "[$timestamp] [$level] $message" >> "$WG_LOG_DIR/wg-core.log"
    
    # Display to console with color
    case "$level" in
        "ERROR")   echo -e "${RED}Error: $message${NC}" ;;
        "WARNING") echo -e "${YELLOW}Warning: $message${NC}" ;;
        "SUCCESS") echo -e "${GREEN}$message${NC}" ;;
        *)         echo "$message" ;;
    esac
}

# Validate system requirements
function validate_system() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_message "ERROR" "This script must be run as root"
        exit 1
    fi

    # Check OS compatibility
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case $ID in
            ubuntu|debian|fedora|centos|rocky|almalinux)
                log_message "SUCCESS" "Operating system $ID is supported"
                ;;
            *)
                log_message "WARNING" "Operating system $ID might not be fully supported"
                ;;
        esac
    else
        log_message "ERROR" "Cannot determine OS type"
        exit 1
    fi
}

# Install required packages
function install_dependencies() {
    source /etc/os-release
    case $ID in
        ubuntu|debian)
            apt-get update
            apt-get install -y wireguard wireguard-tools iptables qrencode
            ;;
        fedora)
            dnf install -y wireguard-tools iptables qrencode
            ;;
        centos|rocky|almalinux)
            dnf install -y epel-release
            dnf install -y wireguard-tools iptables qrencode
            ;;
        *)
            log_message "ERROR" "Unsupported package manager"
            return 1
            ;;
    esac
}

# Check if required commands are available
function check_dependencies() {
    local deps=("wg" "ip" "iptables" "systemctl")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_message "ERROR" "Missing required dependencies: ${missing[*]}"
        install_dependencies
        return 1
    fi
    
    return 0
}

# Generate WireGuard keys
function generate_keys() {
    local name="$1"
    local key_dir="$WG_KEY_DIR/$name"
    
    mkdir -p "$key_dir"
    chmod 700 "$key_dir"
    
    wg genkey | tee "$key_dir/private.key" | wg pubkey > "$key_dir/public.key"
    chmod 600 "$key_dir/private.key"
    chmod 644 "$key_dir/public.key"
    
    if [[ ! -s "$key_dir/private.key" ]] || [[ ! -s "$key_dir/public.key" ]]; then
        log_message "ERROR" "Failed to generate keys for $name"
        return 1
    fi
    
    return 0
}

# Validate IP address format
function validate_ip() {
    local ip="$1"
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    fi
    return 1
}

# Initialize the environment
init_directories

# Export functions
export -f log_message
export -f validate_system
export -f install_dependencies
export -f check_dependencies
export -f generate_keys
export -f validate_ip
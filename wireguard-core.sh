#!/bin/bash

# WireGuard Core Module (wireguard-core.sh)
# This module provides core functionality for WireGuard VPN management including:
# - System checks and validation
# - Installation and dependency management
# - Core configuration functions
# - Security implementation
# - Network interface management

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

# Default configuration values
DEFAULT_PORT=51820
DEFAULT_MTU=1420
DEFAULT_KEEPALIVE=25
DEFAULT_DNS="1.1.1.1,1.0.0.1"
DEFAULT_ALLOWED_IPS="0.0.0.0/0,::/0"

#######################
# Validation Functions
#######################

function validate_system() {
    # Check system requirements and compatibility
    local os_supported=0
    local os_name
    local os_version
    
    # Load OS information
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        os_name=$ID
        os_version=$VERSION_ID
    else
        log_message "ERROR" "Cannot determine OS type"
        return 1
    fi
    
    # Validate supported OS and versions
    case $os_name in
        ubuntu)
            if [[ $(echo "$os_version >= 20.04" | bc) -eq 1 ]]; then
                os_supported=1
            fi
            ;;
        debian)
            if [[ $(echo "$os_version >= 11" | bc) -eq 1 ]]; then
                os_supported=1
            fi
            ;;
        fedora)
            if [[ $os_version -ge 35 ]]; then
                os_supported=1
            fi
            ;;
        centos|rocky|almalinux)
            if [[ $os_version =~ ^8 ]]; then
                os_supported=1
            fi
            ;;
        *)
            log_message "WARNING" "Untested operating system: $os_name"
            ;;
    esac
    
    [[ $os_supported -eq 0 ]] && {
        log_message "ERROR" "Unsupported operating system: $os_name $os_version"
        return 1
    }
    
    return 0
}

function validate_network_interface() {
    local interface=$1
    
    # Check if interface exists
    if ! ip link show "$interface" &>/dev/null; then
        log_message "ERROR" "Interface $interface does not exist"
        return 1
    fi
    
    # Check if interface is up
    if ! ip link show "$interface" | grep -q "UP"; then
        log_message "WARNING" "Interface $interface is down"
        return 1
    }
    
    return 0
}

function validate_port() {
    local port=$1
    
    # Check if port is a number
    if ! [[ $port =~ ^[0-9]+$ ]]; then
        log_message "ERROR" "Invalid port number: $port"
        return 1
    fi
    
    # Check if port is in valid range
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_message "ERROR" "Port must be between 1 and 65535"
        return 1
    fi
    
    # Check if port is already in use
    if netstat -tuln | grep -q ":$port "; then
        log_message "ERROR" "Port $port is already in use"
        return 1
    fi
    
    return 0
}

#######################
# Installation Functions
#######################

function install_dependencies() {
    local os_name
    source /etc/os-release
    os_name=$ID
    
    log_message "INFO" "Installing required dependencies for $os_name"
    
    case $os_name in
        ubuntu|debian)
            apt-get update
            apt-get install -y \
                wireguard \
                wireguard-tools \
                iptables \
                qrencode \
                bc \
                net-tools
            ;;
        fedora)
            dnf install -y \
                wireguard-tools \
                iptables \
                qrencode \
                bc \
                net-tools
            ;;
        centos|rocky|almalinux)
            dnf install -y epel-release
            dnf install -y \
                wireguard-tools \
                iptables \
                qrencode \
                bc \
                net-tools
            ;;
        *)
            log_message "ERROR" "Unsupported package manager"
            return 1
            ;;
    esac
    
    # Verify installation
    local required_packages=("wg" "iptables" "qrencode")
    for package in "${required_packages[@]}"; do
        if ! command -v "$package" &>/dev/null; then
            log_message "ERROR" "Failed to install $package"
            return 1
        fi
    done
    
    return 0
}

#######################
# Security Functions
#######################

function generate_keys() {
    local name=$1
    local key_path="${WG_KEY_DIR}/${name}"
    
    # Create keys directory if it doesn't exist
    mkdir -p "$WG_KEY_DIR"
    chmod 700 "$WG_KEY_DIR"
    
    # Generate private key
    wg genkey | tee "${key_path}.private" | wg pubkey > "${key_path}.public"
    
    # Set proper permissions
    chmod 600 "${key_path}.private"
    chmod 644 "${key_path}.public"
    
    # Verify key generation
    if [[ ! -s "${key_path}.private" ]] || [[ ! -s "${key_path}.public" ]]; then
        log_message "ERROR" "Failed to generate keys for $name"
        return 1
    fi
    
    return 0
}

function secure_configuration() {
    # Secure WireGuard configuration directory
    chmod 700 "$WG_CONFIG_DIR"
    chmod 600 "$WG_CONFIG_DIR"/*
    
    # Ensure proper ownership
    chown -R root:root "$WG_CONFIG_DIR"
    
    # Set up kernel parameters for security
    cat > /etc/sysctl.d/99-wireguard.conf << EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
EOF
    
    sysctl --system
}

#######################
# Network Functions
#######################

function configure_network() {
    local interface=$1
    local subnet=$2
    
    # Configure IP forwarding
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-wireguard.conf
    echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.d/99-wireguard.conf
    sysctl --system
    
    # Set up NAT
    iptables -t nat -A POSTROUTING -s "$subnet" -o "$interface" -j MASQUERADE
    iptables-save > /etc/iptables/rules.v4
    
    # Configure interface
    ip link set dev "$interface" up
    
    # Verify configuration
    if ! ip addr show "$interface" | grep -q "$subnet"; then
        log_message "ERROR" "Failed to configure network interface"
        return 1
    fi
    
    return 0
}

function configure_firewall() {
    local port=$1
    local interface=$2
    
    # Detect firewall type
    if command -v ufw &>/dev/null; then
        configure_ufw "$port" "$interface"
    elif command -v firewall-cmd &>/dev/null; then
        configure_firewalld "$port" "$interface"
    else
        configure_iptables "$port" "$interface"
    fi
}

#######################
# Utility Functions
#######################

function backup_configuration() {
    local backup_name="wg-backup-$(date +%Y%m%d-%H%M%S)"
    local backup_path="${WG_BACKUP_DIR}/${backup_name}"
    
    # Create backup directory
    mkdir -p "$WG_BACKUP_DIR"
    
    # Create backup archive
    tar czf "${backup_path}.tar.gz" -C / etc/wireguard/
    
    # Encrypt backup if gpg is available
    if command -v gpg &>/dev/null; then
        gpg --symmetric "${backup_path}.tar.gz"
        rm "${backup_path}.tar.gz"
        log_message "SUCCESS" "Encrypted backup created: ${backup_path}.tar.gz.gpg"
    else
        log_message "SUCCESS" "Backup created: ${backup_path}.tar.gz"
    fi
}

function log_message() {
    local level=$1
    local message=$2
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$WG_LOG_DIR/wg-core.log"
    
    case $level in
        ERROR)
            echo -e "${RED}Error: $message${NC}" >&2
            ;;
        WARNING)
            echo -e "${YELLOW}Warning: $message${NC}" >&2
            ;;
        SUCCESS)
            echo -e "${GREEN}$message${NC}"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# Export functions for use in other modules
export -f validate_system
export -f validate_network_interface
export -f validate_port
export -f install_dependencies
export -f generate_keys
export -f secure_configuration
export -f configure_network
export -f configure_firewall
export -f backup_configuration
export -f log_message
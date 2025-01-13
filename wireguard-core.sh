#!/bin/bash

# WireGuard Core Module (wireguard-core.sh)
# This module provides core functionality for WireGuard VPN management
# with enhanced error handling and robust dependency management

# Standard color codes for script output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Critical system paths with security considerations
WG_CONFIG_DIR="/etc/wireguard"
WG_KEY_DIR="${WG_CONFIG_DIR}/keys"
WG_LOG_DIR="/var/log/wireguard"
WG_BACKUP_DIR="/var/backup/wireguard"

# Default network settings
DEFAULT_SERVER_PORT=51820
DEFAULT_MTU=1420
DEFAULT_KEEPALIVE=25

# Initialize all required directories with proper permissions
function init_directories() {
    local dirs=(
        "$WG_CONFIG_DIR"
        "$WG_KEY_DIR"
        "$WG_LOG_DIR"
        "$WG_BACKUP_DIR"
        "$WG_CONFIG_DIR/clients"
        "$WG_CONFIG_DIR/peers"
        "$WG_CONFIG_DIR/templates"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chmod 700 "$dir"
            log_message "INFO" "Created directory: $dir"
        fi
    done
}

# Enhanced logging function with timestamps and log rotation
function log_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file="$WG_LOG_DIR/wg-core.log"
    
    # Create log directory if it doesn't exist
    [[ ! -d "$WG_LOG_DIR" ]] && mkdir -p "$WG_LOG_DIR"
    
    # Implement log rotation if file exceeds 10MB
    if [[ -f "$log_file" ]] && [[ $(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null) -gt 10485760 ]]; then
        mv "$log_file" "$log_file.old"
        touch "$log_file"
        chmod 600 "$log_file"
    fi
    
    # Write to log file
    echo "[$timestamp] [$level] $message" >> "$log_file"
    
    # Display to console with color based on level
    case "$level" in
        "ERROR")   echo -e "${RED}Error: $message${NC}" ;;
        "WARNING") echo -e "${YELLOW}Warning: $message${NC}" ;;
        "SUCCESS") echo -e "${GREEN}$message${NC}" ;;
        *)         echo "$message" ;;
    esac
}

# Enhanced system validation with detailed checks
function validate_system() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_message "ERROR" "This script must be run as root"
        exit 1
    fi
    
    # Check OS compatibility and gather system information
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case $ID in
            ubuntu|debian)
                if [[ ${VERSION_ID%%.*} -lt 20 ]]; then
                    log_message "WARNING" "This system may have limited compatibility. Minimum recommended Ubuntu/Debian version is 20.04"
                fi
                ;;
            fedora)
                if [[ $VERSION_ID -lt 32 ]]; then
                    log_message "WARNING" "This system may have limited compatibility. Minimum recommended Fedora version is 32"
                fi
                ;;
            centos|rocky|almalinux)
                if [[ ${VERSION_ID%%.*} -lt 8 ]]; then
                    log_message "WARNING" "This system may have limited compatibility. Minimum recommended version is 8"
                fi
                ;;
            *)
                log_message "WARNING" "Operating system $ID might not be fully supported"
                ;;
        esac
    else
        log_message "ERROR" "Cannot determine OS type"
        exit 1
    fi
    
    # Check system resources
    local mem_total
    mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    if [[ $mem_total -lt 524288 ]]; then  # Less than 512MB
        log_message "WARNING" "System has less than recommended memory (512MB)"
    fi
    
    # Check for required kernel modules
    if ! lsmod | grep -q "wireguard"; then
        log_message "WARNING" "WireGuard kernel module not loaded"
        modprobe wireguard || log_message "ERROR" "Failed to load WireGuard kernel module"
    fi
}

# Enhanced dependency installation with verification
function install_dependencies() {
    source /etc/os-release
    local packages=()
    
    case $ID in
        ubuntu|debian)
            if ! apt-get update; then
                log_message "ERROR" "Failed to update package lists"
                return 1
            fi
            packages=("wireguard" "wireguard-tools" "iptables" "qrencode")
            if ! DEBIAN_FRONTEND=noninteractive apt-get install -y --fix-missing "${packages[@]}"; then
                log_message "WARNING" "Initial package installation had issues, verifying installation..."
                if ! verify_package_installation "${packages[@]}"; then
                    log_message "ERROR" "Failed to verify package installation"
                    return 1
                fi
            fi
            ;;
        fedora)
            packages=("wireguard-tools" "iptables" "qrencode")
            if ! dnf install -y "${packages[@]}"; then
                log_message "WARNING" "Initial package installation had issues, verifying installation..."
                if ! verify_package_installation "${packages[@]}"; then
                    log_message "ERROR" "Failed to verify package installation"
                    return 1
                fi
            fi
            ;;
        centos|rocky|almalinux)
            if ! dnf install -y epel-release; then
                log_message "ERROR" "Failed to install EPEL repository"
                return 1
            fi
            packages=("wireguard-tools" "iptables" "qrencode")
            if ! dnf install -y "${packages[@]}"; then
                log_message "WARNING" "Initial package installation had issues, verifying installation..."
                if ! verify_package_installation "${packages[@]}"; then
                    log_message "ERROR" "Failed to verify package installation"
                    return 1
                fi
            fi
            ;;
        *)
            log_message "ERROR" "Unsupported package manager"
            return 1
            ;;
    esac
    
    # Verify binary availability as additional safety check
    local missing_binaries=()
    for pkg in "${packages[@]}"; do
        if ! command -v "$pkg" &>/dev/null; then
            missing_binaries+=("$pkg")
        fi
    done
    
    if [[ ${#missing_binaries[@]} -gt 0 ]]; then
        log_message "ERROR" "Required binaries not found after installation: ${missing_binaries[*]}"
        return 1
    fi
    
    log_message "SUCCESS" "All required packages installed and verified"
    return 0
}

# Verify package installation status
function verify_package_installation() {
    local missing=()
    
    case $ID in
        ubuntu|debian)
            for pkg in "$@"; do
                if ! dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
                    missing+=("$pkg")
                    log_message "WARNING" "Package $pkg not properly installed"
                fi
            done
            ;;
        fedora|centos|rocky|almalinux)
            for pkg in "$@"; do
                if ! rpm -q "$pkg" >/dev/null 2>&1; then
                    missing+=("$pkg")
                    log_message "WARNING" "Package $pkg not properly installed"
                fi
            done
            ;;
    esac
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_message "ERROR" "Missing packages after installation: ${missing[*]}"
        return 1
    fi
    
    return 0
}

# Enhanced dependency checking with version verification
function check_dependencies() {
    local deps=("wg" "ip" "iptables" "systemctl" "qrencode")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    
    # Check versions of critical components
    if command -v wg &>/dev/null; then
        local wg_version
        wg_version=$(wg --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        log_message "INFO" "WireGuard Tools version: $wg_version"
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_message "ERROR" "Missing required dependencies: ${missing[*]}"
        install_dependencies
        return 1
    fi
    
    return 0
}

# Enhanced key generation with stronger entropy and validation
function generate_keys() {
    local name="$1"
    local key_dir="$WG_KEY_DIR/$name"
    
    # Ensure sufficient entropy
    if [[ $(cat /proc/sys/kernel/random/entropy_avail) -lt 2000 ]]; then
        log_message "WARNING" "Low entropy available. This might slow down key generation"
    fi
    
    mkdir -p "$key_dir"
    chmod 700 "$key_dir"
    
    # Generate private key with extra safety checks
    if ! wg genkey | tee "$key_dir/private.key" >/dev/null; then
        log_message "ERROR" "Failed to generate private key for $name"
        return 1
    fi
    chmod 600 "$key_dir/private.key"
    
    # Generate public key
    if ! wg pubkey < "$key_dir/private.key" > "$key_dir/public.key"; then
        log_message "ERROR" "Failed to generate public key for $name"
        return 1
    fi
    chmod 644 "$key_dir/public.key"
    
    # Validate key generation
    if [[ ! -s "$key_dir/private.key" ]] || [[ ! -s "$key_dir/public.key" ]]; then
        log_message "ERROR" "Key validation failed for $name"
        return 1
    fi
    
    log_message "SUCCESS" "Generated keys for $name"
    return 0
}

# Enhanced IP address validation with IPv6 support
function validate_ip() {
    local ip="$1"
    local ip_type="$2"  # Optional: 'v4' or 'v6'
    
    # Handle IPv4
    if [[ -z "$ip_type" ]] || [[ "$ip_type" == "v4" ]]; then
        if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            local IFS='.'
            read -ra ADDR <<< "$ip"
            for i in "${ADDR[@]}"; do
                if [[ $i -lt 0 ]] || [[ $i -gt 255 ]]; then
                    return 1
                fi
            done
            return 0
        fi
    fi
    
    # Handle IPv6
    if [[ -z "$ip_type" ]] || [[ "$ip_type" == "v6" ]]; then
        if [[ $ip =~ ^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$ ]]; then
            return 0
        fi
    fi
    
    return 1
}

# Network interface validation
function validate_interface() {
    local interface="$1"
    
    # Check if interface exists
    if ! ip link show "$interface" &>/dev/null; then
        return 1
    fi
    
    # Check if interface is up
    if ! ip link show "$interface" | grep -q "UP"; then
        log_message "WARNING" "Interface $interface is down"
    fi
    
    return 0
}

# Port validation with availability check
function validate_port() {
    local port="$1"
    
    # Check if port is a number and within valid range
    if [[ ! $port =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    
    # Check if port is already in use
    if netstat -tuln | grep -q ":$port "; then
        return 1
    fi
    
    return 0
}

# CIDR validation
function validate_cidr() {
    local cidr="$1"
    local ip_part
    local mask_part
    
    IFS='/' read -r ip_part mask_part <<< "$cidr"
    
    # Validate IP part
    if ! validate_ip "$ip_part"; then
        return 1
    fi
    
    # Validate mask part
    if [[ ! $mask_part =~ ^[0-9]+$ ]] || [ "$mask_part" -lt 0 ] || [ "$mask_part" -gt 32 ]; then
        return 1
    fi
    
    return 0
}

# Initialize directories
init_directories

# Export functions
export -f log_message
export -f validate_system
export -f install_dependencies
export -f verify_package_installation
export -f check_dependencies
export -f generate_keys
export -f validate_ip
export -f validate_interface
export -f validate_port
export -f validate_cidr
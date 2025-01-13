#!/bin/bash

# WireGuard Client Configuration Module (client-config.sh)
# This module provides comprehensive client management functionality
# It handles client creation, configuration, and maintenance

# Import core functions using absolute path
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/wireguard-core.sh"

# Configuration paths
CLIENT_BASE_DIR="/etc/wireguard/clients"
CLIENT_CONFIG_DIR="/etc/wireguard/configs"
QR_OUTPUT_DIR="/etc/wireguard/qrcodes"
PEER_CONFIG_DIR="/etc/wireguard/peers"

# Default client settings
DEFAULT_DNS="1.1.1.1,1.0.0.1"
DEFAULT_ALLOWED_IPS="0.0.0.0/0,::/0"
DEFAULT_KEEPALIVE=25
DEFAULT_MTU=1420

# Initialize client directories with proper permissions
function init_client_dirs() {
    local dirs=(
        "$CLIENT_BASE_DIR"
        "$CLIENT_CONFIG_DIR"
        "$QR_OUTPUT_DIR"
        "$PEER_CONFIG_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chmod 700 "$dir"
            log_message "INFO" "Created directory: $dir"
        fi
    done
}

# Enhanced client creation with IP allocation and validation
function create_client() {
    local client_name="$1"
    local tunnel_name="${2:-wg0}"
    local custom_ip="$3"
    local allowed_ips="${4:-$DEFAULT_ALLOWED_IPS}"
    local dns_servers="${5:-$DEFAULT_DNS}"
    local keepalive="${6:-$DEFAULT_KEEPALIVE}"
    
    # Validate client name
    if ! validate_client_name "$client_name"; then
        log_message "ERROR" "Invalid client name: $client_name"
        return 1
    fi
    
    # Create client directory structure
    local client_dir="$CLIENT_BASE_DIR/$client_name"
    mkdir -p "$client_dir"
    chmod 700 "$client_dir"
    
    # Generate client keys
    if ! generate_keys "$client_name"; then
        log_message "ERROR" "Failed to generate keys for client: $client_name"
        return 1
    fi
    
    # Handle IP allocation
    if [[ "$custom_ip" == "auto" ]]; then
        custom_ip=$(allocate_client_ip "$tunnel_name")
        if [[ -z "$custom_ip" ]]; then
            log_message "ERROR" "Failed to allocate IP address for client"
            return 1
        fi
    else
        if ! validate_ip "$custom_ip"; then
            log_message "ERROR" "Invalid IP address: $custom_ip"
            return 1
        fi
        
        if is_ip_in_use "$custom_ip" "$tunnel_name"; then
            log_message "ERROR" "IP address already in use: $custom_ip"
            return 1
        fi
    fi
    
    # Create client configuration
    if ! create_client_config "$client_name" "$custom_ip" "$tunnel_name" "$allowed_ips" "$dns_servers" "$keepalive"; then
        log_message "ERROR" "Failed to create client configuration"
        return 1
    fi
    
    # Generate QR code automatically
    if ! generate_qr_code "$client_name" "$tunnel_name"; then
        log_message "WARNING" "Failed to generate QR code for client: $client_name"
    fi
    
    log_message "SUCCESS" "Client $client_name created successfully with IP: $custom_ip"
    return 0
}

# Enhanced client name validation
function validate_client_name() {
    local name="$1"
    
    # Check length and allowed characters
    if [[ ! $name =~ ^[a-zA-Z0-9]([a-zA-Z0-9_-]{0,30}[a-zA-Z0-9])?$ ]]; then
        log_message "ERROR" "Client name must be 1-32 characters, alphanumeric with _ and -"
        return 1
    fi
    
    # Check for existing client
    if [[ -d "$CLIENT_BASE_DIR/$name" ]]; then
        log_message "ERROR" "Client $name already exists"
        return 1
    fi
    
    # Check for reserved names
    local reserved_names=("server" "wg" "wireguard" "admin" "root")
    for reserved in "${reserved_names[@]}"; do
        if [[ ${name,,} == "$reserved" ]]; then
            log_message "ERROR" "Cannot use reserved name: $name"
            return 1
        fi
    done
    
    return 0
}

# Enhanced client configuration creation
function create_client_config() {
    local client_name="$1"
    local client_ip="$2"
    local tunnel_name="$3"
    local allowed_ips="$4"
    local dns_servers="$5"
    local keepalive="$6"
    
    local config_file="$CLIENT_CONFIG_DIR/${client_name}_${tunnel_name}.conf"
    local priv_key_file="$WG_KEY_DIR/$client_name/private.key"
    local server_pub_key_file="$WG_KEY_DIR/$tunnel_name/public.key"
    
    # Read keys with validation
    if [[ ! -f "$priv_key_file" ]] || [[ ! -f "$server_pub_key_file" ]]; then
        log_message "ERROR" "Missing key files for client configuration"
        return 1
    fi
    
    local priv_key
    priv_key=$(cat "$priv_key_file")
    local server_pub_key
    server_pub_key=$(cat "$server_pub_key_file")
    
    # Get server endpoint
    local server_endpoint
    server_endpoint=$(get_server_endpoint "$tunnel_name")
    
    # Generate client configuration
    cat > "$config_file" << EOF
[Interface]
PrivateKey = ${priv_key}
Address = ${client_ip}/32
DNS = ${dns_servers}
MTU = ${DEFAULT_MTU}

[Peer]
PublicKey = ${server_pub_key}
AllowedIPs = ${allowed_ips}
Endpoint = ${server_endpoint}
PersistentKeepalive = ${keepalive}
EOF
    
    chmod 600 "$config_file"
    
    # Create peer configuration for server
    create_peer_config "$client_name" "$client_ip" "$tunnel_name"
    
    return 0
}

# Create peer configuration for server
function create_peer_config() {
    local client_name="$1"
    local client_ip="$2"
    local tunnel_name="$3"
    
    local peer_file="$PEER_CONFIG_DIR/${client_name}_${tunnel_name}.conf"
    local client_pub_key
    client_pub_key=$(cat "$WG_KEY_DIR/$client_name/public.key")
    
    cat > "$peer_file" << EOF
[Peer]
PublicKey = ${client_pub_key}
AllowedIPs = ${client_ip}/32
PersistentKeepalive = ${DEFAULT_KEEPALIVE}
EOF
    
    chmod 600 "$peer_file"
    
    # Add peer to server configuration
    wg addconf "$tunnel_name" "$peer_file"
    
    return 0
}

# Enhanced QR code generation with validation
function generate_qr_code() {
    local client_name="$1"
    local tunnel_name="${2:-wg0}"
    local config_file="$CLIENT_CONFIG_DIR/${client_name}_${tunnel_name}.conf"
    
    if ! command -v qrencode &>/dev/null; then
        log_message "ERROR" "qrencode not installed"
        return 1
    fi
    
    if [[ ! -f "$config_file" ]]; then
        log_message "ERROR" "Client configuration not found: $config_file"
        return 1
    fi
    
    # Generate QR code with error correction
    qrencode -t png -o "$QR_OUTPUT_DIR/${client_name}_${tunnel_name}.png" -l H < "$config_file"
    chmod 600 "$QR_OUTPUT_DIR/${client_name}_${tunnel_name}.png"
    
    log_message "SUCCESS" "QR code generated for $client_name"
    return 0
}

# Get next available IP address for client
function allocate_client_ip() {
    local tunnel_name="$1"
    local base_ip="10.0.0"
    local start_octet=2
    local max_octet=254
    
    for ((i=start_octet; i<=max_octet; i++)); do
        local ip="${base_ip}.$i"
        if ! is_ip_in_use "$ip" "$tunnel_name"; then
            echo "$ip"
            return 0
        fi
    done
    
    log_message "ERROR" "No available IP addresses in subnet"
    return 1
}

# Check if IP address is already in use
function is_ip_in_use() {
    local ip="$1"
    local tunnel_name="$2"
    
    # Check existing peer configurations
    if grep -r "AllowedIPs = $ip/32" "$PEER_CONFIG_DIR"/* &>/dev/null; then
        return 0
    fi
    
    # Check active WireGuard configuration
    if wg show "$tunnel_name" | grep -q "$ip/32"; then
        return 0
    fi
    
    return 1
}

# Get server endpoint (IP:Port)
function get_server_endpoint() {
    local tunnel_name="$1"
    local config_file="/etc/wireguard/${tunnel_name}.conf"
    
    if [[ ! -f "$config_file" ]]; then
        log_message "ERROR" "Server configuration not found"
        return 1
    fi
    
    # Extract server IP and port
    local server_ip
    server_ip=$(curl -s ifconfig.me)
    local server_port
    server_port=$(grep "ListenPort" "$config_file" | awk '{print $3}')
    
    echo "${server_ip}:${server_port:-51820}"
}

# List all clients with detailed status
function list_clients() {
    local tunnel_name="${1:-wg0}"
    
    echo -e "\nActive Clients for $tunnel_name:"
    echo "================================"
    
    if [[ ! -d "$CLIENT_BASE_DIR" ]]; then
        echo "No clients found"
        return 0
    fi
    
    printf "%-20s %-15s %-20s %-10s\n" "Client Name" "IP Address" "Last Handshake" "Bytes Tx/Rx"
    echo "--------------------------------------------------------------------------------"
    
    for client_dir in "$CLIENT_BASE_DIR"/*; do
        if [[ -d "$client_dir" ]]; then
            local client_name
            client_name=$(basename "$client_dir")
            local client_ip
            client_ip=$(grep "AllowedIPs" "$PEER_CONFIG_DIR/${client_name}_${tunnel_name}.conf" 2>/dev/null | awk '{print $3}' | cut -d'/' -f1)
            
            # Get live status from wg show
            local handshake bytes_tx bytes_rx
            if wg show "$tunnel_name" | grep -q "$client_name"; then
                handshake=$(wg show "$tunnel_name" | grep "$client_name" -A 2 | grep "latest handshake:" | awk '{print $3,$4}')
                bytes_tx=$(wg show "$tunnel_name" | grep "$client_name" -A 2 | grep "transfer:" | awk '{print $2}')
                bytes_rx=$(wg show "$tunnel_name" | grep "$client_name" -A 2 | grep "transfer:" | awk '{print $4}')
            else
                handshake="Never"
                bytes_tx="0"
                bytes_rx="0"
            fi
            
            printf "%-20s %-15s %-20s %-10s\n" "$client_name" "${client_ip:-N/A}" "$handshake" "$bytes_tx/$bytes_rx"
        fi
    done
}

# Remove client with cleanup
function remove_client() {
    local client_name="$1"
    local tunnel_name="${2:-wg0}"
    
    # Check if client exists
    if [[ ! -d "$CLIENT_BASE_DIR/$client_name" ]]; then
        log_message "ERROR" "Client $client_name not found"
        return 1
    fi
    
    # Remove peer from server
    local client_pub_key
    client_pub_key=$(cat "$WG_KEY_DIR/$client_name/public.key" 2>/dev/null)
    if [[ -n "$client_pub_key" ]]; then
        wg set "$tunnel_name" peer "$client_pub_key" remove
    fi
    
    # Remove client files
    rm -rf "$CLIENT_BASE_DIR/$client_name"
    rm -f "$CLIENT_CONFIG_DIR/${client_name}_${tunnel_name}.conf"
    rm -f "$QR_OUTPUT_DIR/${client_name}_${tunnel_name}.png"
    rm -f "$PEER_CONFIG_DIR/${client_name}_${tunnel_name}.conf"
    rm -rf "$WG_KEY_DIR/$client_name"
    
    log_message "SUCCESS" "Client $client_name removed"
    return 0
}

# Initialize client directories
init_client_dirs

# Export functions
export -f create_client
export -f validate_client_name
export -f generate_qr_code
export -f list_clients
export -f remove_client
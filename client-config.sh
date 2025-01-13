#!/bin/bash

# WireGuard Client Configuration Module (client-config.sh)

# Import core functions - using absolute path
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/wireguard-core.sh"

# Configuration paths
CLIENT_BASE_DIR="/etc/wireguard/clients"
CLIENT_CONFIG_DIR="/etc/wireguard/configs"
QR_OUTPUT_DIR="/etc/wireguard/qrcodes"

# Default values
DEFAULT_DNS="1.1.1.1,1.0.0.1"
DEFAULT_ALLOWED_IPS="0.0.0.0/0,::/0"
DEFAULT_KEEPALIVE=25

# Initialize client directories
function init_client_dirs() {
    local dirs=("$CLIENT_BASE_DIR" "$CLIENT_CONFIG_DIR" "$QR_OUTPUT_DIR")
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chmod 700 "$dir"
        fi
    done
}

# Create a new client
function create_client() {
    local client_name="$1"
    local tunnel_name="${2:-wg0}"
    local custom_ip="$3"
    
    # Validate client name
    if ! validate_client_name "$client_name"; then
        log_message "ERROR" "Invalid client name: $client_name"
        return 1
    fi
    
    # Create client directory
    local client_dir="$CLIENT_BASE_DIR/$client_name"
    mkdir -p "$client_dir"
    chmod 700 "$client_dir"
    
    # Generate client keys
    if ! generate_keys "$client_name"; then
        log_message "ERROR" "Failed to generate keys for client: $client_name"
        return 1
    fi
    
    # Create client configuration
    if ! create_client_config "$client_name" "$custom_ip" "$tunnel_name"; then
        log_message "ERROR" "Failed to create client configuration"
        return 1
    fi
    
    log_message "SUCCESS" "Client $client_name created successfully"
    return 0
}

# Validate client name
function validate_client_name() {
    local name="$1"
    
    # Check length and characters
    if [[ ! $name =~ ^[a-zA-Z0-9_-]{1,32}$ ]]; then
        return 1
    fi
    
    # Check if client already exists
    if [[ -d "$CLIENT_BASE_DIR/$name" ]]; then
        return 1
    fi
    
    return 0
}

# Create client configuration file
function create_client_config() {
    local client_name="$1"
    local client_ip="$2"
    local tunnel_name="$3"
    
    local config_file="$CLIENT_CONFIG_DIR/${client_name}_${tunnel_name}.conf"
    local priv_key_file="$WG_KEY_DIR/$client_name/private.key"
    local server_pub_key_file="$WG_KEY_DIR/$tunnel_name/public.key"
    
    # Read keys
    local priv_key
    priv_key=$(cat "$priv_key_file")
    local server_pub_key
    server_pub_key=$(cat "$server_pub_key_file")
    
    # Generate configuration
    cat > "$config_file" << EOF
[Interface]
PrivateKey = ${priv_key}
Address = ${client_ip}/32
DNS = ${DEFAULT_DNS}

[Peer]
PublicKey = ${server_pub_key}
AllowedIPs = ${DEFAULT_ALLOWED_IPS}
PersistentKeepalive = ${DEFAULT_KEEPALIVE}
EOF
    
    chmod 600 "$config_file"
    return 0
}

# Generate QR code for client configuration
function generate_qr_code() {
    local client_name="$1"
    local tunnel_name="${2:-wg0}"
    local config_file="$CLIENT_CONFIG_DIR/${client_name}_${tunnel_name}.conf"
    
    if ! command -v qrencode &>/dev/null; then
        log_message "ERROR" "qrencode not found"
        return 1
    fi
    
    if [[ ! -f "$config_file" ]]; then
        log_message "ERROR" "Configuration file not found"
        return 1
    fi
    
    qrencode -t png -o "$QR_OUTPUT_DIR/${client_name}.png" < "$config_file"
    chmod 600 "$QR_OUTPUT_DIR/${client_name}.png"
    
    log_message "SUCCESS" "QR code generated for $client_name"
    return 0
}

# List all clients
function list_clients() {
    local tunnel_name="${1:-wg0}"
    
    echo "Active Clients for $tunnel_name:"
    echo "--------------------------------"
    
    if [[ -d "$CLIENT_BASE_DIR" ]]; then
        for client in "$CLIENT_BASE_DIR"/*; do
            if [[ -d "$client" ]]; then
                local client_name
                client_name=$(basename "$client")
                echo "- $client_name"
            fi
        done
    else
        echo "No clients found"
    fi
}

# Remove client
function remove_client() {
    local client_name="$1"
    local tunnel_name="${2:-wg0}"
    
    # Check if client exists
    if [[ ! -d "$CLIENT_BASE_DIR/$client_name" ]]; then
        log_message "ERROR" "Client $client_name not found"
        return 1
    fi
    
    # Remove client files
    rm -rf "$CLIENT_BASE_DIR/$client_name"
    rm -f "$CLIENT_CONFIG_DIR/${client_name}_${tunnel_name}.conf"
    rm -f "$QR_OUTPUT_DIR/${client_name}.png"
    
    log_message "SUCCESS" "Client $client_name removed"
    return 0
}

# Initialize directories
init_client_dirs

# Export functions
export -f create_client
export -f validate_client_name
export -f generate_qr_code
export -f list_clients
export -f remove_client
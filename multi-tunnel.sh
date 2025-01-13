#!/bin/bash

# WireGuard Multi-Tunnel Support Module (multi-tunnel.sh)

# Import core functions - using absolute path
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/wireguard-core.sh"

# Configuration paths
TUNNEL_BASE_DIR="/etc/wireguard/tunnels"
TUNNEL_KEYS_DIR="/etc/wireguard/keys/tunnels"
TUNNEL_CONFIG_DIR="/etc/wireguard/configs/tunnels"

# Default network settings
IPV4_SUBNETS=(
    "10.0.0.0/24"
    "10.0.1.0/24"
    "10.0.2.0/24"
    "10.0.3.0/24"
)

IPV6_SUBNETS=(
    "fd00:1::/64"
    "fd00:2::/64"
    "fd00:3::/64"
    "fd00:4::/64"
)

# Initialize tunnel directories
function init_tunnel_dirs() {
    local dirs=("$TUNNEL_BASE_DIR" "$TUNNEL_KEYS_DIR" "$TUNNEL_CONFIG_DIR")
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chmod 700 "$dir"
        fi
    done
}

# Create new tunnel
function create_tunnel() {
    local tunnel_name="$1"
    local port="$2"
    
    # Validate tunnel name
    if ! validate_tunnel_name "$tunnel_name"; then
        log_message "ERROR" "Invalid tunnel name: $tunnel_name"
        return 1
    fi
    
    # Create tunnel directory
    local tunnel_dir="$TUNNEL_BASE_DIR/$tunnel_name"
    mkdir -p "$tunnel_dir"
    chmod 700 "$tunnel_dir"
    
    # Generate tunnel keys
    if ! generate_keys "$tunnel_name"; then
        log_message "ERROR" "Failed to generate keys for tunnel: $tunnel_name"
        return 1
    fi
    
    # Create tunnel configuration
    if create_tunnel_config "$tunnel_name" "$port"; then
        log_message "SUCCESS" "Tunnel $tunnel_name created successfully"
        setup_tunnel_networking "$tunnel_name"
        return 0
    else
        log_message "ERROR" "Failed to create tunnel configuration"
        return 1
    fi
}

# Validate tunnel name
function validate_tunnel_name() {
    local name="$1"
    
    # Check length and characters
    if [[ ! $name =~ ^[a-zA-Z0-9_]{1,15}$ ]]; then
        return 1
    fi
    
    # Check if tunnel already exists
    if [[ -d "$TUNNEL_BASE_DIR/$name" ]]; then
        return 1
    fi
    
    return 0
}

# Create tunnel configuration
function create_tunnel_config() {
    local tunnel_name="$1"
    local port="$2"
    local config_file="$TUNNEL_CONFIG_DIR/$tunnel_name.conf"
    
    # Read private key
    local priv_key
    priv_key=$(cat "$WG_KEY_DIR/$tunnel_name/private.key")
    
    # Get available subnet
    local subnet
    subnet=$(get_available_subnet)
    
    # Create configuration
    cat > "$config_file" << EOF
[Interface]
PrivateKey = ${priv_key}
Address = ${subnet}
ListenPort = ${port}
SaveConfig = true

PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOF
    
    chmod 600 "$config_file"
    return 0
}

# Set up tunnel networking
function setup_tunnel_networking() {
    local tunnel_name="$1"
    
    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # Start tunnel service
    systemctl enable "wg-quick@$tunnel_name"
    systemctl start "wg-quick@$tunnel_name"
    
    # Verify tunnel is running
    if ! wg show "$tunnel_name" &>/dev/null; then
        log_message "ERROR" "Failed to start tunnel $tunnel_name"
        return 1
    fi
    
    return 0
}

# Get available subnet
function get_available_subnet() {
    for subnet in "${IPV4_SUBNETS[@]}"; do
        if ! is_subnet_used "$subnet"; then
            echo "$subnet"
            return 0
        fi
    done
    
    log_message "ERROR" "No available subnets"
    return 1
}

# Check if subnet is in use
function is_subnet_used() {
    local subnet="$1"
    
    for conf in "$TUNNEL_CONFIG_DIR"/*.conf; do
        if [[ -f "$conf" ]] && grep -q "$subnet" "$conf"; then
            return 0
        fi
    done
    
    return 1
}

# List all tunnels
function list_tunnels() {
    echo "Active WireGuard Tunnels:"
    echo "------------------------"
    
    if [[ -d "$TUNNEL_BASE_DIR" ]]; then
        for tunnel in "$TUNNEL_BASE_DIR"/*; do
            if [[ -d "$tunnel" ]]; then
                local tunnel_name
                tunnel_name=$(basename "$tunnel")
                local status
                
                if systemctl is-active --quiet "wg-quick@$tunnel_name"; then
                    status="active"
                else
                    status="inactive"
                fi
                
                echo "- $tunnel_name ($status)"
            fi
        done
    else
        echo "No tunnels found"
    fi
}

# Remove tunnel
function remove_tunnel() {
    local tunnel_name="$1"
    
    # Check if tunnel exists
    if [[ ! -d "$TUNNEL_BASE_DIR/$tunnel_name" ]]; then
        log_message "ERROR" "Tunnel $tunnel_name not found"
        return 1
    fi
    
    # Stop and disable tunnel service
    systemctl stop "wg-quick@$tunnel_name"
    systemctl disable "wg-quick@$tunnel_name"
    
    # Remove tunnel files
    rm -rf "$TUNNEL_BASE_DIR/$tunnel_name"
    rm -f "$TUNNEL_CONFIG_DIR/$tunnel_name.conf"
    
    log_message "SUCCESS" "Tunnel $tunnel_name removed"
    return 0
}

# Initialize directories
init_tunnel_dirs

# Export functions
export -f create_tunnel
export -f list_tunnels
export -f remove_tunnel
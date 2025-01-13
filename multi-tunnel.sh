#!/bin/bash

# WireGuard Multi-Tunnel Support Module (multi-tunnel.sh)
# This module provides comprehensive support for managing multiple WireGuard tunnels,
# including creation, configuration, monitoring, and maintenance of multiple VPN tunnels
# on a single server.

# Import required core functions
source "./wireguard-core.sh"

# Configuration paths and constants
TUNNEL_BASE_DIR="/etc/wireguard"
TUNNEL_CONFIG_DIR="/etc/wireguard/tunnels"
TUNNEL_STATUS_DIR="/var/run/wireguard"

# Networking constants
IPV4_SUBNETS=(
    "10.0.0.0/24"
    "10.0.1.0/24"
    "10.0.2.0/24"
    "10.0.3.0/24"
    "10.0.4.0/24"
)
IPV6_SUBNETS=(
    "fd00:1::/64"
    "fd00:2::/64"
    "fd00:3::/64"
    "fd00:4::/64"
    "fd00:5::/64"
)

# Port range for tunnels
PORT_RANGE_START=51820
PORT_RANGE_END=51920

#########################
# Tunnel Creation Functions
#########################

function create_new_tunnel() {
    local tunnel_name=$1
    local custom_port=$2
    
    # Validate tunnel name
    if ! validate_tunnel_name "$tunnel_name"; then
        log_message "ERROR" "Invalid tunnel name: $tunnel_name"
        return 1
    }
    
    # Prepare tunnel directory
    local tunnel_dir="$TUNNEL_CONFIG_DIR/$tunnel_name"
    mkdir -p "$tunnel_dir"
    chmod 700 "$tunnel_dir"
    
    # Generate tunnel keys
    if ! generate_tunnel_keys "$tunnel_name"; then
        log_message "ERROR" "Failed to generate keys for tunnel: $tunnel_name"
        return 1
    }
    
    # Assign port and subnets
    local port
    if [[ -n $custom_port ]]; then
        if ! validate_port "$custom_port"; then
            log_message "ERROR" "Invalid custom port: $custom_port"
            return 1
        }
        port=$custom_port
    else
        port=$(assign_available_port)
    fi
    
    local ipv4_subnet
    local ipv6_subnet
    if ! assign_tunnel_subnets "$tunnel_name"; then
        log_message "ERROR" "Failed to assign subnets for tunnel: $tunnel_name"
        return 1
    }
    
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

function generate_tunnel_keys() {
    local tunnel_name=$1
    local key_dir="$TUNNEL_CONFIG_DIR/$tunnel_name/keys"
    
    mkdir -p "$key_dir"
    chmod 700 "$key_dir"
    
    # Generate server keys
    wg genkey | tee "$key_dir/server_private.key" | wg pubkey > "$key_dir/server_public.key"
    
    # Set secure permissions
    chmod 600 "$key_dir/server_private.key"
    chmod 644 "$key_dir/server_public.key"
    
    # Verify key generation
    if [[ ! -s "$key_dir/server_private.key" ]] || [[ ! -s "$key_dir/server_public.key" ]]; then
        return 1
    fi
    return 0
}

#########################
# Configuration Functions
#########################

function create_tunnel_config() {
    local tunnel_name=$1
    local port=$2
    local config_file="$TUNNEL_CONFIG_DIR/$tunnel_name/${tunnel_name}.conf"
    
    # Load tunnel keys
    local private_key
    private_key=$(cat "$TUNNEL_CONFIG_DIR/$tunnel_name/keys/server_private.key")
    
    # Get assigned subnets
    local ipv4_subnet
    local ipv6_subnet
    ipv4_subnet=$(get_tunnel_subnet "$tunnel_name" "ipv4")
    ipv6_subnet=$(get_tunnel_subnet "$tunnel_name" "ipv6")
    
    # Create basic configuration
    cat > "$config_file" << EOF
[Interface]
PrivateKey = ${private_key}
Address = ${ipv4_subnet%/*}.1/${ipv4_subnet#*/},${ipv6_subnet%/*}1/${ipv6_subnet#*/}
ListenPort = ${port}
SaveConfig = true

# PostUp and PostDown rules
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${MAIN_INTERFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${MAIN_INTERFACE} -j MASQUERADE
EOF
    
    chmod 600 "$config_file"
    
    # Create tunnel status tracking file
    touch "$TUNNEL_STATUS_DIR/$tunnel_name.status"
    
    return 0
}

function setup_tunnel_networking() {
    local tunnel_name=$1
    local config_file="$TUNNEL_CONFIG_DIR/$tunnel_name/${tunnel_name}.conf"
    
    # Enable IP forwarding
    sysctl -w net.ipv4.ip_forward=1
    sysctl -w net.ipv6.conf.all.forwarding=1
    
    # Start the tunnel
    systemctl enable "wg-quick@$tunnel_name"
    systemctl start "wg-quick@$tunnel_name"
    
    # Verify tunnel is up
    if ! wg show "$tunnel_name" &>/dev/null; then
        log_message "ERROR" "Failed to start tunnel $tunnel_name"
        return 1
    fi
    
    return 0
}

#########################
# Management Functions
#########################

function list_tunnels() {
    local tunnels=()
    
    # Get all tunnel configurations
    while IFS= read -r -d '' conf_file; do
        local tunnel_name
        tunnel_name=$(basename "$conf_file" .conf)
        tunnels+=("$tunnel_name")
    done < <(find "$TUNNEL_CONFIG_DIR" -type f -name "*.conf" -print0)
    
    # Display tunnel information
    printf "%-15s %-15s %-10s %-20s\n" "Tunnel" "Status" "Port" "Clients"
    echo "------------------------------------------------"
    
    for tunnel in "${tunnels[@]}"; do
        local status
        local port
        local clients
        
        status=$(get_tunnel_status "$tunnel")
        port=$(get_tunnel_port "$tunnel")
        clients=$(count_tunnel_clients "$tunnel")
        
        printf "%-15s %-15s %-10s %-20s\n" "$tunnel" "$status" "$port" "$clients"
    done
}

function get_tunnel_status() {
    local tunnel_name=$1
    
    if systemctl is-active --quiet "wg-quick@$tunnel_name"; then
        echo "active"
    else
        echo "inactive"
    fi
}

function get_tunnel_port() {
    local tunnel_name=$1
    local config_file="$TUNNEL_CONFIG_DIR/$tunnel_name/${tunnel_name}.conf"
    
    grep -Po 'ListenPort = \K[0-9]+' "$config_file" || echo "N/A"
}

function count_tunnel_clients() {
    local tunnel_name=$1
    local config_file="$TUNNEL_CONFIG_DIR/$tunnel_name/${tunnel_name}.conf"
    
    grep -c "\[Peer\]" "$config_file" || echo "0"
}

#########################
# Maintenance Functions
#########################

function monitor_tunnel_performance() {
    local tunnel_name=$1
    
    # Get tunnel statistics
    local stats
    stats=$(wg show "$tunnel_name")
    
    # Parse and display statistics
    echo "Tunnel Performance Monitor: $tunnel_name"
    echo "-----------------------------------"
    echo "$stats" | while IFS= read -r line; do
        case "$line" in
            *transfer:*)
                parse_transfer_stats "$line"
                ;;
            *handshake:*)
                parse_handshake_stats "$line"
                ;;
        esac
    done
}

function cleanup_inactive_peers() {
    local tunnel_name=$1
    local inactive_threshold=${2:-180} # Default 3 hours in seconds
    
    local config_file="$TUNNEL_CONFIG_DIR/$tunnel_name/${tunnel_name}.conf"
    local tmp_config="${config_file}.tmp"
    
    # Get current timestamp
    local current_time
    current_time=$(date +%s)
    
    # Process each peer
    while read -r line; do
        if [[ $line == *"[Peer]"* ]]; then
            local peer_pubkey
            peer_pubkey=$(wg show "$tunnel_name" dump | grep "$line" | cut -f 1)
            local last_handshake
            last_handshake=$(wg show "$tunnel_name" dump | grep "$peer_pubkey" | cut -f 5)
            
            # Check if peer is inactive
            if (( current_time - last_handshake > inactive_threshold )); then
                log_message "INFO" "Removing inactive peer: $peer_pubkey"
                continue
            fi
        fi
        echo "$line" >> "$tmp_config"
    done < "$config_file"
    
    # Replace original config with cleaned version
    mv "$tmp_config" "$config_file"
    chmod 600 "$config_file"
    
    # Reload tunnel configuration
    wg syncconf "$tunnel_name" <(wg-quick strip "$tunnel_name")
}

#########################
# Utility Functions
#########################

function validate_tunnel_name() {
    local name=$1
    
    # Check length
    if [[ ${#name} -lt 1 || ${#name} -gt 15 ]]; then
        return 1
    fi
    
    # Check characters
    if ! [[ $name =~ ^[a-zA-Z0-9_]+$ ]]; then
        return 1
    fi
    
    # Check if tunnel already exists
    if [[ -d "$TUNNEL_CONFIG_DIR/$name" ]]; then
        return 1
    fi
    
    return 0
}

function assign_available_port() {
    local port=$PORT_RANGE_START
    
    while [[ $port -le $PORT_RANGE_END ]]; do
        if ! check_port_used "$port"; then
            echo "$port"
            return 0
        fi
        ((port++))
    done
    
    return 1
}

function assign_tunnel_subnets() {
    local tunnel_name=$1
    
    # Find available IPv4 subnet
    for subnet in "${IPV4_SUBNETS[@]}"; do
        if ! check_subnet_used "$subnet"; then
            mark_subnet_used "$subnet" "$tunnel_name"
            echo "$subnet" > "$TUNNEL_CONFIG_DIR/$tunnel_name/ipv4_subnet"
            break
        fi
    done
    
    # Find available IPv6 subnet
    for subnet in "${IPV6_SUBNETS[@]}"; do
        if ! check_subnet_used "$subnet"; then
            mark_subnet_used "$subnet" "$tunnel_name"
            echo "$subnet" > "$TUNNEL_CONFIG_DIR/$tunnel_name/ipv6_subnet"
            break
        fi
    done
    
    # Verify subnet assignment
    if [[ ! -f "$TUNNEL_CONFIG_DIR/$tunnel_name/ipv4_subnet" ]] || \
       [[ ! -f "$TUNNEL_CONFIG_DIR/$tunnel_name/ipv6_subnet" ]]; then
        return 1
    fi
    
    return 0
}

# Export functions
export -f create_new_tunnel
export -f list_tunnels
export -f monitor_tunnel_performance
export -f cleanup_inactive_peers
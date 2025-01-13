#!/bin/bash

# WireGuard Multi-Tunnel Support Module (multi-tunnel.sh)
# This module enables management of multiple WireGuard tunnels
# providing isolation and traffic separation capabilities

# Import core functions using absolute path
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/wireguard-core.sh"

# Configuration paths for tunnel management
TUNNEL_BASE_DIR="/etc/wireguard/tunnels"
TUNNEL_KEYS_DIR="/etc/wireguard/keys/tunnels"
TUNNEL_CONFIG_DIR="/etc/wireguard/configs/tunnels"

# Network configuration arrays for tunnel addressing
IPV4_SUBNETS=(
    "10.0.0.0/24"  # Primary subnet
    "10.0.1.0/24"  # Secondary subnet
    "10.0.2.0/24"  # Tertiary subnet
    "10.0.3.0/24"  # Quaternary subnet
    "10.0.4.0/24"  # Quinary subnet
)

IPV6_SUBNETS=(
    "fd00:1::/64"  # Primary IPv6 subnet
    "fd00:2::/64"  # Secondary IPv6 subnet
    "fd00:3::/64"  # Tertiary IPv6 subnet
    "fd00:4::/64"  # Quaternary IPv6 subnet
)

# Initialize tunnel directory structure
function init_tunnel_dirs() {
    # Create and secure all required directories
    local dirs=(
        "$TUNNEL_BASE_DIR"
        "$TUNNEL_KEYS_DIR"
        "$TUNNEL_CONFIG_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chmod 700 "$dir"
            log_message "INFO" "Created directory: $dir"
        fi
    done
}

# Create a new WireGuard tunnel with comprehensive setup
function create_tunnel() {
    local tunnel_name="$1"
    local port="$2"
    local subnet_index="${3:-0}"  # Optional subnet selection
    
    # Validate tunnel name
    if ! validate_tunnel_name "$tunnel_name"; then
        log_message "ERROR" "Invalid tunnel name: $tunnel_name"
        return 1
    fi
    
    # Validate and check port availability
    if ! validate_port "$port"; then
        log_message "ERROR" "Invalid or in-use port: $port"
        return 1
    fi
    
    # Create tunnel directory structure
    local tunnel_dir="$TUNNEL_BASE_DIR/$tunnel_name"
    mkdir -p "$tunnel_dir"
    chmod 700 "$tunnel_dir"
    
    # Generate tunnel keys
    if ! generate_keys "$tunnel_name"; then
        log_message "ERROR" "Failed to generate keys for tunnel: $tunnel_name"
        return 1
    fi
    
    # Create tunnel configuration
    if create_tunnel_config "$tunnel_name" "$port" "$subnet_index"; then
        log_message "SUCCESS" "Tunnel $tunnel_name created successfully"
        setup_tunnel_networking "$tunnel_name"
        return 0
    else
        log_message "ERROR" "Failed to create tunnel configuration"
        return 1
    fi
}

# Validate tunnel name against security requirements
function validate_tunnel_name() {
    local name="$1"
    
    # Check length and allowed characters
    if [[ ! $name =~ ^[a-zA-Z0-9_]{1,15}$ ]]; then
        log_message "ERROR" "Tunnel name must be 1-15 characters, alphanumeric with underscore"
        return 1
    fi
    
    # Check for existing tunnel
    if [[ -d "$TUNNEL_BASE_DIR/$name" ]]; then
        log_message "ERROR" "Tunnel $name already exists"
        return 1
    fi
    
    # Check for reserved names
    local reserved=("wg0" "wg" "all" "any" "none" "default")
    for r in "${reserved[@]}"; do
        if [[ ${name,,} == "$r" ]]; then
            log_message "ERROR" "Cannot use reserved name: $name"
            return 1
        fi
    done
    
    return 0
}

# Create comprehensive tunnel configuration
function create_tunnel_config() {
    local tunnel_name="$1"
    local port="$2"
    local subnet_index="$3"
    local config_file="$TUNNEL_CONFIG_DIR/$tunnel_name.conf"
    
    # Read private key
    local priv_key
    priv_key=$(cat "$WG_KEY_DIR/$tunnel_name/private.key")
    
    # Get available subnet
    local subnet
    if ! subnet=$(get_available_subnet "$subnet_index"); then
        log_message "ERROR" "Failed to allocate subnet"
        return 1
    fi
    
    # Determine primary network interface
    local primary_interface
    primary_interface=$(get_primary_interface)
    
    # Create comprehensive configuration
    cat > "$config_file" << EOF
[Interface]
PrivateKey = ${priv_key}
Address = ${subnet%/*}.1/${subnet#*/}
ListenPort = ${port}
SaveConfig = true

# Network configuration
PostUp = sysctl -w net.ipv4.ip_forward=1
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -o ${primary_interface} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o ${primary_interface} -j MASQUERADE

# Advanced settings
MTU = ${DEFAULT_MTU}
Table = off
EOF
    
    chmod 600 "$config_file"
    return 0
}

# Set up networking for tunnel
function setup_tunnel_networking() {
    local tunnel_name="$1"
    
    # Enable IP forwarding if not already enabled
    if [[ $(sysctl -n net.ipv4.ip_forward) -ne 1 ]]; then
        sysctl -w net.ipv4.ip_forward=1
        echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.d/99-wireguard.conf
    fi
    
    # Enable IPv6 forwarding if available
    if [[ -f /proc/sys/net/ipv6/conf/all/forwarding ]]; then
        sysctl -w net.ipv6.conf.all.forwarding=1
        echo "net.ipv6.conf.all.forwarding = 1" >> /etc/sysctl.d/99-wireguard.conf
    fi
    
    # Create and enable systemd service
    create_systemd_service "$tunnel_name"
    
    # Start tunnel service
    systemctl enable --now "wg-quick@$tunnel_name"
    
    # Verify tunnel is running
    if ! wg show "$tunnel_name" &>/dev/null; then
        log_message "ERROR" "Failed to start tunnel $tunnel_name"
        return 1
    fi
    
    return 0
}

# Create systemd service for tunnel
function create_systemd_service() {
    local tunnel_name="$1"
    local service_file="/etc/systemd/system/wg-quick@${tunnel_name}.service"
    
    cat > "$service_file" << EOF
[Unit]
Description=WireGuard tunnel for %I
After=network-online.target nss-lookup.target
Wants=network-online.target nss-lookup.target
Documentation=man:wg-quick(8)
Documentation=man:wg(8)

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/wg-quick up %i
ExecStop=/usr/bin/wg-quick down %i
Environment=WG_ENDPOINT_RESOLUTION_RETRIES=infinity

[Install]
WantedBy=multi-user.target
EOF
    
    chmod 644 "$service_file"
    systemctl daemon-reload
}

# Get available subnet for new tunnel
function get_available_subnet() {
    local preferred_index="$1"
    
    # Try preferred index first if specified
    if [[ -n "$preferred_index" ]] && [[ $preferred_index -lt ${#IPV4_SUBNETS[@]} ]]; then
        local preferred_subnet="${IPV4_SUBNETS[$preferred_index]}"
        if ! is_subnet_used "$preferred_subnet"; then
            echo "$preferred_subnet"
            return 0
        fi
    fi
    
    # Otherwise, find first available subnet
    for subnet in "${IPV4_SUBNETS[@]}"; do
        if ! is_subnet_used "$subnet"; then
            echo "$subnet"
            return 0
        fi
    done
    
    log_message "ERROR" "No available subnets"
    return 1
}

# Check if subnet is already in use
function is_subnet_used() {
    local subnet="$1"
    local base_ip="${subnet%/*}"  # Remove CIDR notation
    
    # Check existing configurations
    for conf in "$TUNNEL_CONFIG_DIR"/*.conf; do
        if [[ -f "$conf" ]] && grep -q "Address = $base_ip" "$conf"; then
            return 0
        fi
    done
    
    # Check active interfaces
    if ip addr show | grep -q "$subnet"; then
        return 0
    fi
    
    return 1
}

# Get primary network interface
function get_primary_interface() {
    # Try to get the interface with default route
    local interface
    interface=$(ip route | grep default | awk '{print $5}' | head -n1)
    
    if [[ -z "$interface" ]]; then
        # Fallback to first non-loopback interface
        interface=$(ip link show | grep -v lo | grep -v wg | awk -F: '$0 !~ "^ " {print $2}' | head -n1 | tr -d '[:space:]')
    fi
    
    echo "${interface:-eth0}"  # Default to eth0 if nothing else found
}

# List all tunnels with comprehensive status
function list_tunnels() {
    echo -e "\nWireGuard Tunnel Status"
    echo "======================"
    
    if [[ ! -d "$TUNNEL_BASE_DIR" ]]; then
        echo "No tunnels configured"
        return 0
    fi
    
    printf "%-15s %-15s %-10s %-15s %-10s\n" "Tunnel Name" "IP Address" "Port" "Status" "Peers"
    echo "--------------------------------------------------------------"
    
    for tunnel in "$TUNNEL_BASE_DIR"/*; do
        if [[ -d "$tunnel" ]]; then
            local tunnel_name
            tunnel_name=$(basename "$tunnel")
            local status
            local ip_address
            local port
            local peer_count
            
            if systemctl is-active --quiet "wg-quick@$tunnel_name"; then
                status="active"
                ip_address=$(wg show "$tunnel_name" | grep "interface:" -A 1 | grep "public key:" -B 1 | head -n1 | awk '{print $2}')
                port=$(wg show "$tunnel_name" listen-port)
                peer_count=$(wg show "$tunnel_name" peers | wc -l)
            else
                status="inactive"
                ip_address="N/A"
                port="N/A"
                peer_count=0
            fi
            
            printf "%-15s %-15s %-10s %-15s %-10s\n" "$tunnel_name" "$ip_address" "$port" "$status" "$peer_count"
        fi
    done
}

# Remove tunnel with comprehensive cleanup
function remove_tunnel() {
    local tunnel_name="$1"
    
    # Validate tunnel exists
    if [[ ! -d "$TUNNEL_BASE_DIR/$tunnel_name" ]]; then
        log_message "ERROR" "Tunnel $tunnel_name not found"
        return 1
    fi
    
    # Stop and disable tunnel service
    systemctl stop "wg-quick@$tunnel_name"
    systemctl disable "wg-quick@$tunnel_name"
    
    # Remove systemd service
    rm -f "/etc/systemd/system/wg-quick@${tunnel_name}.service"
    systemctl daemon-reload
    
    # Remove all tunnel files
    rm -rf "$TUNNEL_BASE_DIR/$tunnel_name"
    rm -f "$TUNNEL_CONFIG_DIR/$tunnel_name.conf"
    rm -rf "$WG_KEY_DIR/$tunnel_name"
    
    # Remove any associated peer configurations
    rm -f "$PEER_CONFIG_DIR/"*"_${tunnel_name}.conf"
    
    log_message "SUCCESS" "Tunnel $tunnel_name removed"
    return 0
}

# Show detailed tunnel information
function show_tunnel_info() {
    local tunnel_name="$1"
    
    if ! wg show "$tunnel_name" &>/dev/null; then
        log_message "ERROR" "Tunnel $tunnel_name not found or not active"
        return 1
    fi
    
    echo -e "\nDetailed Information for Tunnel: $tunnel_name"
    echo "========================================"
    
    # Show interface information
    echo "Interface Configuration:"
    wg show "$tunnel_name"
    
    # Show routing information
    echo -e "\nRouting Information:"
    ip route show table all | grep "$tunnel_name"
    
    # Show active connections
    echo -e "\nActive Connections:"
    netstat -tnp | grep "${tunnel_name}"
    
    return 0
}

# Initialize directories
init_tunnel_dirs

# Export functions
export -f create_tunnel
export -f list_tunnels
export -f remove_tunnel
export -f show_tunnel_info
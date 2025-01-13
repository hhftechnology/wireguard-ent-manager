#!/bin/bash

# WireGuard Client Configuration Module (client-config.sh)
# This module handles all client-related operations including:
# - Client creation and management
# - Key generation and management
# - Configuration file generation
# - QR code generation for mobile clients
# - Batch operations for multiple clients

# Import required core functions
source "./wireguard-core.sh"

# Configuration Constants
CLIENT_BASE_DIR="/etc/wireguard/clients"
CLIENT_TEMPLATE_DIR="/etc/wireguard/templates"
QR_OUTPUT_DIR="/etc/wireguard/qrcodes"
MAX_CLIENTS=254  # Maximum number of clients per subnet

# Client IP Management
declare -A USED_IPS
declare -A CLIENT_TUNNELS

#########################
# Client Creation Functions
#########################

function create_new_client() {
    local client_name=$1
    local tunnel_name=${2:-wg0}
    local custom_ip=$3
    
    # Validate client name
    if ! validate_client_name "$client_name"; then
        log_message "ERROR" "Invalid client name: $client_name"
        return 1
    }
    
    # Create client directories
    mkdir -p "$CLIENT_BASE_DIR/$client_name"
    chmod 700 "$CLIENT_BASE_DIR/$client_name"
    
    # Generate client keys
    if ! generate_client_keys "$client_name"; then
        log_message "ERROR" "Failed to generate keys for client: $client_name"
        return 1
    }
    
    # Assign IP address
    local client_ip
    if [[ -n $custom_ip ]]; then
        if ! validate_ip_address "$custom_ip"; then
            log_message "ERROR" "Invalid custom IP address: $custom_ip"
            return 1
        }
        client_ip=$custom_ip
    else
        client_ip=$(assign_client_ip "$tunnel_name")
    fi
    
    # Create client configuration
    if create_client_config "$client_name" "$client_ip" "$tunnel_name"; then
        log_message "SUCCESS" "Client $client_name created successfully"
        generate_qr_code "$client_name"
        return 0
    else
        log_message "ERROR" "Failed to create client configuration"
        return 1
    fi
}

function generate_client_keys() {
    local client_name=$1
    local key_dir="$CLIENT_BASE_DIR/$client_name/keys"
    
    mkdir -p "$key_dir"
    chmod 700 "$key_dir"
    
    # Generate private key
    wg genkey | tee "$key_dir/private.key" | wg pubkey > "$key_dir/public.key"
    wg genpsk > "$key_dir/preshared.key"
    
    # Set secure permissions
    chmod 600 "$key_dir/private.key" "$key_dir/preshared.key"
    chmod 644 "$key_dir/public.key"
    
    # Verify key generation
    if [[ ! -s "$key_dir/private.key" ]] || [[ ! -s "$key_dir/public.key" ]]; then
        return 1
    fi
    return 0
}

#########################
# Configuration Functions
#########################

function create_client_config() {
    local client_name=$1
    local client_ip=$2
    local tunnel_name=$3
    local config_dir="$CLIENT_BASE_DIR/$client_name"
    
    # Load keys
    local private_key
    local public_key
    local preshared_key
    private_key=$(cat "$config_dir/keys/private.key")
    public_key=$(cat "$config_dir/keys/public.key")
    preshared_key=$(cat "$config_dir/keys/preshared.key")
    
    # Get server configuration
    local server_public_key
    local server_endpoint
    local server_port
    server_public_key=$(get_server_pubkey "$tunnel_name")
    server_endpoint=$(get_server_endpoint)
    server_port=$(get_server_port "$tunnel_name")
    
    # Create client configuration file
    cat > "$config_dir/${tunnel_name}.conf" << EOF
[Interface]
PrivateKey = ${private_key}
Address = ${client_ip}/32
DNS = ${CLIENT_DNS:-$DEFAULT_DNS}

[Peer]
PublicKey = ${server_public_key}
PresharedKey = ${preshared_key}
Endpoint = ${server_endpoint}:${server_port}
AllowedIPs = ${ALLOWED_IPS:-$DEFAULT_ALLOWED_IPS}
PersistentKeepalive = ${PERSISTENT_KEEPALIVE:-$DEFAULT_KEEPALIVE}
EOF
    
    chmod 600 "$config_dir/${tunnel_name}.conf"
    
    # Add client to server configuration
    add_client_to_server "$client_name" "$public_key" "$preshared_key" "$client_ip" "$tunnel_name"
    
    return 0
}

function configure_client_dns() {
    local client_name=$1
    local tunnel_name=$2
    
    echo "Configure DNS for client $client_name"
    echo "1) Use default DNS (${DEFAULT_DNS})"
    echo "2) Use custom DNS servers"
    echo "3) Use split DNS configuration"
    
    local choice
    read -rp "Select DNS configuration [1-3]: " choice
    
    case $choice in
        2)
            read -rp "Enter primary DNS server: " primary_dns
            read -rp "Enter secondary DNS server (optional): " secondary_dns
            if [[ -n $secondary_dns ]]; then
                CLIENT_DNS="${primary_dns},${secondary_dns}"
            else
                CLIENT_DNS="${primary_dns}"
            fi
            ;;
        3)
            configure_split_dns "$client_name" "$tunnel_name"
            ;;
        *)
            CLIENT_DNS="$DEFAULT_DNS"
            ;;
    esac
}

function configure_split_dns() {
    local client_name=$1
    local tunnel_name=$2
    local config_file="$CLIENT_BASE_DIR/$client_name/${tunnel_name}.conf"
    
    echo "Configure Split DNS"
    echo "Enter domain and DNS server pairs (empty line to finish):"
    
    local domains=()
    local servers=()
    
    while true; do
        read -rp "Domain (or empty to finish): " domain
        [[ -z $domain ]] && break
        
        read -rp "DNS server for $domain: " server
        domains+=("$domain")
        servers+=("$server")
    done
    
    # Create split DNS configuration
    local dns_config=""
    for i in "${!domains[@]}"; do
        dns_config+="DNS = ${servers[$i]}"
        dns_config+="DNSName = ${domains[$i]}"
    done
    
    # Update client configuration
    sed -i "/\[Interface\]/a ${dns_config}" "$config_file"
}

#########################
# Batch Operation Functions
#########################

function process_batch_file() {
    local batch_file=$1
    local tunnel_name=${2:-wg0}
    local result=0
    
    # Validate batch file
    if ! [[ -f $batch_file ]]; then
        log_message "ERROR" "Batch file not found: $batch_file"
        return 1
    fi
    
    # Process each line
    while IFS=, read -r name ip allowed_ips dns keepalive; do
        # Skip comments and empty lines
        [[ $name =~ ^#.*$ || -z $name ]] && continue
        
        log_message "INFO" "Processing client: $name"
        
        # Set custom variables for this client
        ALLOWED_IPS="$allowed_ips"
        CLIENT_DNS="$dns"
        PERSISTENT_KEEPALIVE="$keepalive"
        
        # Create client
        if ! create_new_client "$name" "$tunnel_name" "$ip"; then
            log_message "ERROR" "Failed to create client: $name"
            result=1
        fi
        
    done < "$batch_file"
    
    return $result
}

#########################
# Utility Functions
#########################

function validate_client_name() {
    local name=$1
    
    # Check length
    if [[ ${#name} -lt 1 || ${#name} -gt 32 ]]; then
        return 1
    fi
    
    # Check characters
    if ! [[ $name =~ ^[a-zA-Z0-9_-]+$ ]]; then
        return 1
    fi
    
    # Check if client already exists
    if [[ -d "$CLIENT_BASE_DIR/$name" ]]; then
        return 1
    fi
    
    return 0
}

function assign_client_ip() {
    local tunnel_name=$1
    local base_ip
    base_ip=$(get_tunnel_subnet "$tunnel_name")
    
    # Find next available IP
    for i in $(seq 2 $MAX_CLIENTS); do
        local potential_ip="${base_ip%.*}.$i"
        if ! check_ip_used "$potential_ip"; then
            mark_ip_used "$potential_ip"
            echo "$potential_ip"
            return 0
        fi
    done
    
    log_message "ERROR" "No available IP addresses"
    return 1
}

function generate_qr_code() {
    local client_name=$1
    local config_file="$CLIENT_BASE_DIR/$client_name/wg0.conf"
    
    # Create QR code directory if it doesn't exist
    mkdir -p "$QR_OUTPUT_DIR"
    chmod 700 "$QR_OUTPUT_DIR"
    
    # Generate QR code if qrencode is available
    if command -v qrencode >/dev/null 2>&1; then
        qrencode -t png -o "$QR_OUTPUT_DIR/$client_name.png" < "$config_file"
        chmod 600 "$QR_OUTPUT_DIR/$client_name.png"
        log_message "SUCCESS" "QR code generated: $QR_OUTPUT_DIR/$client_name.png"
        return 0
    fi
    
    log_message "WARNING" "qrencode not available, skipping QR code generation"
    return 1
}

# Export functions
export -f create_new_client
export -f process_batch_file
export -f validate_client_name
export -f generate_qr_code
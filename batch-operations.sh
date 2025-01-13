#!/bin/bash

# WireGuard Batch Operations Module (batch-operations.sh)

# Import core functions using absolute path
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/wireguard-core.sh"

# Define directory structure
BATCH_DIR="/etc/wireguard/batch"
TEMPLATE_DIR="/etc/wireguard/templates"
IMPORT_DIR="/etc/wireguard/imports"
EXPORT_DIR="/etc/wireguard/exports"

# Processing limits
MAX_BATCH_SIZE=100
BATCH_PROCESS_DELAY=0.5

# Initialize directories
function init_batch_dirs() {
    for dir in "$BATCH_DIR" "$TEMPLATE_DIR" "$IMPORT_DIR" "$EXPORT_DIR"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chmod 700 "$dir"
        fi
    done
}

# Validate IP address format
function validate_ip_address() {
    local ip=$1
    if [[ $ip == "auto" ]]; then
        return 0
    fi
    
    # Check IPv4 format
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        # Validate each octet
        local IFS='.'
        read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -lt 0 || $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Validate CIDR notation
function validate_cidr() {
    local cidr=$1
    local ip_part
    local mask_part
    
    # Split IP and mask
    IFS='/' read -r ip_part mask_part <<< "$cidr"
    
    # Validate IP part
    if ! validate_ip_address "$ip_part"; then
        return 1
    fi
    
    # Validate mask part
    if [[ ! $mask_part =~ ^[0-9]+$ ]] || \
       [[ $mask_part -lt 0 ]] || \
       [[ $mask_part -gt 32 ]]; then
        return 1
    fi
    
    return 0
}

# Validate allowed IPs format
function validate_allowed_ips() {
    local allowed_ips=$1
    
    # Split on commas and semicolons
    local IFS=',;'
    read -ra CIDRS <<< "$allowed_ips"
    
    for cidr in "${CIDRS[@]}"; do
        if ! validate_cidr "${cidr// /}"; then
            return 1
        fi
    done
    
    return 0
}

# Validate DNS server format
function validate_dns_servers() {
    local dns_servers=$1
    
    # Split on commas and semicolons
    local IFS=',;'
    read -ra SERVERS <<< "$dns_servers"
    
    for server in "${SERVERS[@]}"; do
        if ! validate_ip_address "${server// /}"; then
            return 1
        fi
    done
    
    return 0
}

# Process batch clients
function process_batch_clients() {
    local batch_file=$1
    local tunnel_name=${2:-wg0}
    local results_file="$BATCH_DIR/results_$(date +%Y%m%d_%H%M%S).log"
    
    if [[ ! -f $batch_file ]]; then
        log_message "ERROR" "Batch file not found: $batch_file"
        return 1
    fi
    
    # Initialize results file
    echo "Batch Processing Results - $(date)" > "$results_file"
    echo "----------------------------------------" >> "$results_file"
    
    local total=0
    local successful=0
    local failed=0
    
    # Process each line
    while IFS=, read -r name ip allowed_ips dns keepalive; do
        # Skip header and comments
        [[ $name =~ ^#.*$ || $name == "name" ]] && continue
        
        ((total++))
        log_message "INFO" "Processing client: $name"
        
        if create_batch_client "$name" "$ip" "$allowed_ips" "$dns" "$keepalive" "$tunnel_name"; then
            echo "[SUCCESS] $name" >> "$results_file"
            ((successful++))
        else
            echo "[FAILED] $name" >> "$results_file"
            ((failed++))
        fi
        
        sleep "$BATCH_PROCESS_DELAY"
    done < "$batch_file"
    
    # Write summary
    {
        echo "----------------------------------------"
        echo "Batch Processing Summary"
        echo "Total Processed: $total"
        echo "Successful: $successful"
        echo "Failed: $failed"
    } >> "$results_file"
    
    cat "$results_file"
    return $(( failed > 0 ))
}

# Validate batch client inputs
function validate_batch_client_inputs() {
    local name=$1
    local ip=$2
    local allowed_ips=$3
    local dns=$4
    local keepalive=$5
    
    # Validate client name (alphanumeric, underscore, hyphen)
    if [[ ! $name =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_message "ERROR" "Invalid client name format: $name"
        return 1
    fi
    
    # Validate IP address
    if ! validate_ip_address "$ip"; then
        log_message "ERROR" "Invalid IP address: $ip"
        return 1
    fi
    
    # Validate allowed IPs
    if ! validate_allowed_ips "$allowed_ips"; then
        log_message "ERROR" "Invalid AllowedIPs format: $allowed_ips"
        return 1
    fi
    
    # Validate DNS servers
    if ! validate_dns_servers "$dns"; then
        log_message "ERROR" "Invalid DNS format: $dns"
        return 1
    fi
    
    # Validate keepalive value
    if ! [[ $keepalive =~ ^[0-9]+$ ]]; then
        log_message "ERROR" "Invalid keepalive value: $keepalive"
        return 1
    fi
    
    return 0
}

# Create batch client
function create_batch_client() {
    local name=$1
    local ip=$2
    local allowed_ips=$3
    local dns=$4
    local keepalive=$5
    local tunnel=$6
    
    # Validate inputs
    if ! validate_batch_client_inputs "$name" "$ip" "$allowed_ips" "$dns" "$keepalive"; then
        return 1
    fi
    
    # Create client configuration
    create_client "$name" "$tunnel" "$ip" "$allowed_ips" "$dns" "$keepalive"
}

# Create batch template
function create_batch_template() {
    local template_file="$TEMPLATE_DIR/batch_template.csv"
    
    cat > "$template_file" << 'EOF'
name,ip,allowed_ips,dns,keepalive
client1,auto,0.0.0.0/0,1.1.1.1,25
client2,10.0.0.2,192.168.1.0/24,8.8.8.8,30
client3,10.0.0.3,10.0.0.0/24,1.1.1.1,25
EOF
    
    chmod 600 "$template_file"
    log_message "SUCCESS" "Batch template created: $template_file"
    return 0
}

# Initialize directories
init_batch_dirs

# Export functions
export -f process_batch_clients
export -f create_batch_template
export -f validate_batch_client_inputs
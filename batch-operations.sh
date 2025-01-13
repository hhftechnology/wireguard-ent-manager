#!/bin/bash

# WireGuard Batch Operations Module (batch-operations.sh)

# First, let's ensure we have access to our core functions
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/wireguard-core.sh"

# Define our directory structure
BATCH_DIR="/etc/wireguard/batch"
TEMPLATE_DIR="/etc/wireguard/templates"
IMPORT_DIR="/etc/wireguard/imports"
EXPORT_DIR="/etc/wireguard/exports"

# Constants for batch processing
MAX_BATCH_SIZE=100
BATCH_PROCESS_DELAY=0.5

# Initialize our working directories
function init_batch_dirs() {
    local directories=(
        "$BATCH_DIR"
        "$TEMPLATE_DIR"
        "$IMPORT_DIR"
        "$EXPORT_DIR"
    )
    
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chmod 700 "$dir"
        fi
    done
}

# Process a batch of client configurations
function process_batch_clients() {
    local batch_file="$1"
    local tunnel_name="${2:-wg0}"
    local results_file="${BATCH_DIR}/results_$(date +%Y%m%d_%H%M%S).log"
    
    # First, validate our batch file
    if ! validate_batch_file "$batch_file"; then
        log_message "ERROR" "Invalid batch file: $batch_file"
        return 1
    fi
    
    # Initialize our counters
    local total=0
    local successful=0
    local failed=0
    
    # Create our results file
    echo "Batch Processing Results - $(date)" > "$results_file"
    echo "----------------------------------------" >> "$results_file"
    
    # Process each line in the batch file
    while IFS=, read -r name ip allowed_ips dns keepalive; do
        # Skip header and comments
        [[ "$name" =~ ^#.*$ || "$name" == "name" ]] && continue
        
        ((total++))
        if create_batch_client "$name" "$ip" "$allowed_ips" "$dns" "$keepalive" "$tunnel_name"; then
            log_message "SUCCESS" "Created client: $name"
            echo "[SUCCESS] $name" >> "$results_file"
            ((successful++))
        else
            log_message "ERROR" "Failed to create client: $name"
            echo "[FAILED] $name" >> "$results_file"
            ((failed++))
        fi
        
        sleep "$BATCH_PROCESS_DELAY"
    done < "$batch_file"
    
    # Write summary to results file
    {
        echo "----------------------------------------"
        echo "Batch Processing Summary"
        echo "Total Processed: $total"
        echo "Successful: $successful"
        echo "Failed: $failed"
        echo "----------------------------------------"
    } >> "$results_file"
    
    cat "$results_file"
    return $((failed > 0))
}

# Create a single client from batch data
function create_batch_client() {
    local name="$1"
    local ip="$2"
    local allowed_ips="$3"
    local dns="$4"
    local keepalive="$5"
    local tunnel="$6"
    
    # Ensure we have wireguard installed
    if ! command -v wg >/dev/null 2>&1; then
        log_message "ERROR" "WireGuard is not installed"
        install_dependencies
        return 1
    fi
    
    # Validate our inputs
    if ! validate_batch_client_inputs "$name" "$ip" "$allowed_ips" "$dns" "$keepalive"; then
        return 1
    fi
    
    # Create the client using the client-config module
    if [[ "$ip" == "auto" ]]; then
        create_client "$name" "$tunnel" "" "$allowed_ips" "$dns" "$keepalive"
    else
        create_client "$name" "$tunnel" "$ip" "$allowed_ips" "$dns" "$keepalive"
    fi
}

# Validate the batch file format and content
function validate_batch_file() {
    local file="$1"
    
    # Check if file exists and is readable
    if [[ ! -f "$file" ]] || [[ ! -r "$file" ]]; then
        log_message "ERROR" "Batch file not found or not readable"
        return 1
    fi
    
    # Check file format
    local header
    read -r header < "$file"
    
    # Verify required columns
    local required_columns=("name" "ip" "allowed_ips" "dns" "keepalive")
    for column in "${required_columns[@]}"; do
        if ! echo "$header" | grep -q "$column"; then
            log_message "ERROR" "Missing required column: $column"
            return 1
        fi
    done
    
    # Check file size
    local line_count
    line_count=$(wc -l < "$file")
    if ((line_count > MAX_BATCH_SIZE + 1)); then
        log_message "ERROR" "Batch file exceeds maximum size of $MAX_BATCH_SIZE entries"
        return 1
    fi
    
    return 0
}

# Validate client input data
function validate_batch_client_inputs() {
    local name="$1"
    local ip="$2"
    local allowed_ips="$3"
    local dns="$4"
    local keepalive="$5"
    
    # Validate name
    if ! [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_message "ERROR" "Invalid client name format: $name"
        return 1
    fi
    
    # Validate IP if not auto
    if [[ "$ip" != "auto" ]]; then
        if ! validate_ip "$ip"; then
            log_message "ERROR" "Invalid IP address: $ip"
            return 1
        fi
    fi
    
    # Basic CIDR validation
    if ! [[ "$allowed_ips" =~ ^[0-9./,;:]+$ ]]; then
        log_message "ERROR" "Invalid AllowedIPs format: $allowed_ips"
        return 1
    fi
    
    # Basic DNS validation
    if ! [[ "$dns" =~ ^[0-9.;:]+$ ]]; then
        log_message "ERROR" "Invalid DNS format: $dns"
        return 1
    fi
    
    # Validate keepalive is a number
    if ! [[ "$keepalive" =~ ^[0-9]+$ ]]; then
        log_message "ERROR" "Invalid keepalive value: $keepalive"
        return 1
    fi
    
    return 0
}

# Create a template for batch operations
function create_batch_template() {
    local template_file="${TEMPLATE_DIR}/batch_template.csv"
    
    cat > "$template_file" << EOF
name,ip,allowed_ips,dns,keepalive
client1,auto,0.0.0.0/0,1.1.1.1,25
client2,10.0.0.2,192.168.1.0/24,8.8.8.8,30
client3,10.0.0.3,10.0.0.0/24;192.168.0.0/16,1.1.1.1;8.8.8.8,0
EOF
    
    log_message "SUCCESS" "Batch template created: $template_file"
    chmod 600 "$template_file"
    return 0
}

# Initialize our directories when the script is loaded
init_batch_dirs

# Export our functions for use in other scripts
export -f process_batch_clients
export -f create_batch_template
export -f validate_batch_file
export -f validate_batch_client_inputs
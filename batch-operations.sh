#!/bin/bash

# WireGuard Batch Operations Module (batch-operations.sh)
# This module enables bulk operations and automation for WireGuard management
# It provides tools for handling multiple clients and configurations efficiently

# Import core functions using absolute path
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "${SCRIPT_DIR}/wireguard-core.sh"
source "${SCRIPT_DIR}/client-config.sh"

# Define directory structure for batch operations
BATCH_DIR="/etc/wireguard/batch"
TEMPLATE_DIR="/etc/wireguard/templates"
IMPORT_DIR="/etc/wireguard/imports"
EXPORT_DIR="/etc/wireguard/exports"

# Processing limits for safety and performance
MAX_BATCH_SIZE=100
BATCH_PROCESS_DELAY=0.5
MAX_PARALLEL_JOBS=5

# Initialize batch operation directories
function init_batch_dirs() {
    # Create and secure all required directories
    local dirs=(
        "$BATCH_DIR"
        "$TEMPLATE_DIR"
        "$IMPORT_DIR"
        "$EXPORT_DIR"
        "$BATCH_DIR/logs"
        "$BATCH_DIR/temp"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            chmod 700 "$dir"
            log_message "INFO" "Created directory: $dir"
        fi
    done
}

# Process batch client operations with comprehensive validation
function process_batch_clients() {
    local batch_file="$1"
    local tunnel_name="${2:-wg0}"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local results_file="$BATCH_DIR/logs/results_${timestamp}.log"
    local error_file="$BATCH_DIR/logs/errors_${timestamp}.log"
    
    # Validate input file
    if [[ ! -f $batch_file ]]; then
        log_message "ERROR" "Batch file not found: $batch_file"
        return 1
    fi
    
    # Initialize results tracking
    {
        echo "Batch Processing Results - $(date)"
        echo "Batch File: $batch_file"
        echo "Tunnel: $tunnel_name"
        echo "----------------------------------------"
    } > "$results_file"
    
    # Initialize counters
    local total=0
    local successful=0
    local failed=0
    local skipped=0
    
    # Create temporary working directory
    local temp_dir
    temp_dir=$(mktemp -d -p "$BATCH_DIR/temp")
    chmod 700 "$temp_dir"
    
    # Process each line with proper error handling
    while IFS=, read -r name ip allowed_ips dns keepalive; do
        # Skip header and comments
        [[ $name =~ ^#.*$ || $name == "name" ]] && continue
        
        ((total++))
        
        # Check batch size limit
        if [[ $total -gt $MAX_BATCH_SIZE ]]; then
            log_message "WARNING" "Batch size limit ($MAX_BATCH_SIZE) exceeded. Remaining entries skipped."
            ((skipped++))
            continue
        fi
        
        log_message "INFO" "Processing client: $name"
        
        # Validate all input parameters
        if ! validate_batch_client_inputs "$name" "$ip" "$allowed_ips" "$dns" "$keepalive"; then
            echo "[FAILED] $name - Invalid input parameters" >> "$results_file"
            echo "Client $name: Input validation failed" >> "$error_file"
            ((failed++))
            continue
        fi
        
        # Create client with captured output
        if create_batch_client "$name" "$ip" "$allowed_ips" "$dns" "$keepalive" "$tunnel_name" > "$temp_dir/${name}.log" 2>&1; then
            echo "[SUCCESS] $name" >> "$results_file"
            ((successful++))
        else
            echo "[FAILED] $name - See error log for details" >> "$results_file"
            cat "$temp_dir/${name}.log" >> "$error_file"
            ((failed++))
        fi
        
        # Add delay to prevent resource exhaustion
        sleep "$BATCH_PROCESS_DELAY"
        
    done < "$batch_file"
    
    # Generate comprehensive summary
    {
        echo "----------------------------------------"
        echo "Batch Processing Summary"
        echo "Total Processed: $total"
        echo "Successful: $successful"
        echo "Failed: $failed"
        echo "Skipped: $skipped"
        echo "----------------------------------------"
        echo "Detailed error log: $error_file"
        echo "Timestamp: $(date)"
    } >> "$results_file"
    
    # Display results
    cat "$results_file"
    
    # Cleanup temporary files
    rm -rf "$temp_dir"
    
    return $(( failed > 0 ))
}

# Validate batch client input parameters
function validate_batch_client_inputs() {
    local name="$1"
    local ip="$2"
    local allowed_ips="$3"
    local dns="$4"
    local keepalive="$5"
    
    # Validate client name
    if [[ ! $name =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,31}$ ]]; then
        log_message "ERROR" "Invalid client name format: $name"
        return 1
    fi
    
    # Validate IP address (allow 'auto')
    if [[ $ip != "auto" ]] && ! validate_ip "$ip"; then
        log_message "ERROR" "Invalid IP address: $ip"
        return 1
    fi
    
    # Validate allowed IPs format
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
    if ! [[ $keepalive =~ ^[0-9]+$ ]] || [[ $keepalive -lt 0 ]] || [[ $keepalive -gt 3600 ]]; then
        log_message "ERROR" "Invalid keepalive value: $keepalive"
        return 1
    fi
    
    return 0
}

# Validate DNS server format
function validate_dns_servers() {
    local dns_servers="$1"
    
    # Split on commas and validate each server
    IFS=',' read -ra SERVERS <<< "$dns_servers"
    
    for server in "${SERVERS[@]}"; do
        # Remove whitespace
        server="${server// /}"
        if ! validate_ip "$server"; then
            return 1
        fi
    done
    
    return 0
}

# Validate allowed IPs format
function validate_allowed_ips() {
    local allowed_ips="$1"
    
    # Split on commas and validate each CIDR
    IFS=',' read -ra CIDRS <<< "$allowed_ips"
    
    for cidr in "${CIDRS[@]}"; do
        # Remove whitespace
        cidr="${cidr// /}"
        if ! validate_cidr "$cidr"; then
            return 1
        fi
    done
    
    return 0
}

# Create batch client with enhanced error handling
function create_batch_client() {
    local name="$1"
    local ip="$2"
    local allowed_ips="$3"
    local dns="$4"
    local keepalive="$5"
    local tunnel="$6"
    
    # Create client using existing client creation function
    if ! create_client "$name" "$tunnel" "$ip" "$allowed_ips" "$dns" "$keepalive"; then
        log_message "ERROR" "Failed to create client: $name"
        return 1
    fi
    
    # Generate QR code if successful
    if ! generate_qr_code "$name" "$tunnel"; then
        log_message "WARNING" "Failed to generate QR code for client: $name"
    fi
    
    return 0
}

# Create template for batch operations
function create_batch_template() {
    local template_file="$TEMPLATE_DIR/batch_template.csv"
    
    # Create comprehensive template with examples
    cat > "$template_file" << 'EOF'
# WireGuard Batch Client Template
# Format: name,ip,allowed_ips,dns,keepalive
# Example entries below:

# Auto IP assignment example
client1,auto,0.0.0.0/0,1.1.1.1,25

# Custom IP assignment example
client2,10.0.0.2,192.168.1.0/24,8.8.8.8;8.8.4.4,30

# Split tunnel example
client3,10.0.0.3,10.0.0.0/24;192.168.0.0/16,1.1.1.1,25

# Name format: alphanumeric with _ and -
# IP format: IPv4 address or 'auto'
# AllowedIPs: CIDR notation, multiple entries separated by ;
# DNS: IPv4 addresses, multiple entries separated by ;
# Keepalive: seconds (15-3600)
EOF
    
    chmod 600 "$template_file"
    log_message "SUCCESS" "Batch template created: $template_file"
    return 0
}

# Export client configurations in bulk
function export_configs() {
    local tunnel_name="${1:-wg0}"
    local export_dir="$EXPORT_DIR/export_$(date +%Y%m%d_%H%M%S)"
    
    mkdir -p "$export_dir"
    chmod 700 "$export_dir"
    
    # Export all client configurations
    local count=0
    for conf in "$CLIENT_CONFIG_DIR"/*"_${tunnel_name}.conf"; do
        if [[ -f "$conf" ]]; then
            cp "$conf" "$export_dir/"
            ((count++))
        fi
    done
    
    # Export QR codes if they exist
    mkdir -p "$export_dir/qrcodes"
    for qr in "$QR_OUTPUT_DIR"/*"_${tunnel_name}.png"; do
        if [[ -f "$qr" ]]; then
            cp "$qr" "$export_dir/qrcodes/"
        fi
    done
    
    # Create summary file
    {
        echo "Export Summary - $(date)"
        echo "Tunnel: $tunnel_name"
        echo "Configurations exported: $count"
        echo "Export location: $export_dir"
    } > "$export_dir/summary.txt"
    
    # Create archive
    tar -czf "${export_dir}.tar.gz" -C "$(dirname "$export_dir")" "$(basename "$export_dir")"
    rm -rf "$export_dir"
    
    log_message "SUCCESS" "Configurations exported to ${export_dir}.tar.gz"
    return 0
}

# Import client configurations in bulk
function import_configs() {
    local import_file="$1"
    local tunnel_name="${2:-wg0}"
    
    if [[ ! -f "$import_file" ]]; then
        log_message "ERROR" "Import file not found: $import_file"
        return 1
    fi
    
    # Create temporary working directory
    local temp_dir
    temp_dir=$(mktemp -d -p "$BATCH_DIR/temp")
    chmod 700 "$temp_dir"
    
    # Extract archive
    tar -xzf "$import_file" -C "$temp_dir"
    
    # Process configurations
    local count=0
    local failed=0
    for conf in "$temp_dir"/**/*.conf; do
        if [[ -f "$conf" ]]; then
            local client_name
            client_name=$(basename "$conf" | sed "s/_${tunnel_name}.conf//")
            
            if cp "$conf" "$CLIENT_CONFIG_DIR/"; then
                ((count++))
            else
                ((failed++))
                log_message "ERROR" "Failed to import configuration for $client_name"
            fi
        fi
    done
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log_message "SUCCESS" "Imported $count configurations (Failed: $failed)"
    return $(( failed > 0 ))
}

# Initialize directories
init_batch_dirs

# Export functions
export -f process_batch_clients
export -f create_batch_template
export -f export_configs
export -f import_configs
export -f validate_batch_client_inputs
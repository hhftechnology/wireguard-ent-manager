#!/bin/bash

# WireGuard Batch Operations Module (batch-operations.sh)
# This module handles all batch processing operations for WireGuard configuration,
# including client creation, configuration updates, and maintenance tasks.
# It provides robust error handling and detailed logging for bulk operations.

# Import required modules
source "./wireguard-core.sh"
source "./client-config.sh"

# Configuration directories
BATCH_DIR="/etc/wireguard/batch"
TEMPLATE_DIR="/etc/wireguard/templates"
IMPORT_DIR="/etc/wireguard/imports"
EXPORT_DIR="/etc/wireguard/exports"

# Batch processing limits
MAX_BATCH_SIZE=100
BATCH_PROCESS_DELAY=0.5

#########################
# Batch Client Operations
#########################

function process_batch_clients() {
    local batch_file=$1
    local tunnel_name=${2:-wg0}
    local results_file="$BATCH_DIR/results_$(date +%Y%m%d_%H%M%S).log"
    
    # Validate batch file
    if ! validate_batch_file "$batch_file"; then
        log_message "ERROR" "Invalid batch file format: $batch_file"
        return 1
    }
    
    # Create results directory if it doesn't exist
    mkdir -p "$BATCH_DIR"
    
    # Initialize counters
    local total=0
    local successful=0
    local failed=0
    
    # Process header to get column positions
    local -A columns
    read -r header < "$batch_file"
    IFS=',' read -ra headers <<< "$header"
    for i in "${!headers[@]}"; do
        columns[${headers[$i]}]=$i
    done
    
    # Log start of batch processing
    log_message "INFO" "Starting batch processing for tunnel $tunnel_name"
    echo "Batch Processing Results - $(date)" > "$results_file"
    echo "----------------------------------------" >> "$results_file"
    
    # Process each line
    while IFS=, read -ra line; do
        # Skip header
        [[ "${line[0]}" == "name" ]] && continue
        
        # Extract values using column positions
        local client_name="${line[${columns[name]}]}"
        local client_ip="${line[${columns[ip]}]:-auto}"
        local allowed_ips="${line[${columns[allowed_ips]}]:-0.0.0.0/0}"
        local dns_servers="${line[${columns[dns]}]:-1.1.1.1}"
        local keepalive="${line[${columns[keepalive]}]:-25}"
        
        ((total++))
        
        # Process client with error handling
        if create_batch_client "$client_name" "$client_ip" "$allowed_ips" "$dns_servers" "$keepalive" "$tunnel_name"; then
            log_message "SUCCESS" "Created client: $client_name"
            echo "[SUCCESS] $client_name" >> "$results_file"
            ((successful++))
        else
            log_message "ERROR" "Failed to create client: $client_name"
            echo "[FAILED] $client_name - Check logs for details" >> "$results_file"
            ((failed++))
        fi
        
        # Add delay to prevent system overload
        sleep "$BATCH_PROCESS_DELAY"
        
    done < "$batch_file"
    
    # Generate summary
    {
        echo "----------------------------------------"
        echo "Batch Processing Summary"
        echo "Total Processed: $total"
        echo "Successful: $successful"
        echo "Failed: $failed"
        echo "----------------------------------------"
    } >> "$results_file"
    
    # Display results
    cat "$results_file"
    return $(( failed > 0 ))
}

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
    }
    
    # Create client using client-config module
    if [[ $ip == "auto" ]]; then
        create_new_client "$name" "$tunnel" "" "$allowed_ips" "$dns" "$keepalive"
    else
        create_new_client "$name" "$tunnel" "$ip" "$allowed_ips" "$dns" "$keepalive"
    fi
}

#########################
# Batch Export Operations
#########################

function export_batch_configs() {
    local tunnel_name=$1
    local export_type=${2:-"all"}
    local export_dir="$EXPORT_DIR/$(date +%Y%m%d_%H%M%S)"
    
    mkdir -p "$export_dir"
    
    case $export_type in
        "all")
            export_all_configs "$tunnel_name" "$export_dir"
            ;;
        "active")
            export_active_configs "$tunnel_name" "$export_dir"
            ;;
        "unused")
            export_unused_configs "$tunnel_name" "$export_dir"
            ;;
        *)
            log_message "ERROR" "Invalid export type: $export_type"
            return 1
            ;;
    esac
    
    # Create export manifest
    create_export_manifest "$export_dir"
    
    # Archive the export
    create_export_archive "$export_dir"
}

function export_all_configs() {
    local tunnel_name=$1
    local export_dir=$2
    
    for client in "$TUNNEL_CONFIG_DIR/$tunnel_name/clients"/*; do
        [[ -d $client ]] || continue
        local client_name=$(basename "$client")
        cp "$client/${tunnel_name}.conf" "$export_dir/${client_name}.conf"
    done
}

#########################
# Batch Import Operations
#########################

function import_batch_configs() {
    local import_file=$1
    local tunnel_name=$2
    
    # Validate import file
    if ! validate_import_file "$import_file"; then
        log_message "ERROR" "Invalid import file: $import_file"
        return 1
    }
    
    # Create temporary directory for extraction
    local temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT
    
    # Extract configurations
    if [[ $import_file == *.tar.gz ]]; then
        tar xzf "$import_file" -C "$temp_dir"
    elif [[ $import_file == *.zip ]]; then
        unzip "$import_file" -d "$temp_dir"
    else
        log_message "ERROR" "Unsupported import format"
        return 1
    fi
    
    # Process each configuration file
    for config in "$temp_dir"/*.conf; do
        import_single_config "$config" "$tunnel_name"
    done
}

#########################
# Utility Functions
#########################

function validate_batch_file() {
    local file=$1
    
    # Check if file exists and is readable
    if [[ ! -f $file ]] || [[ ! -r $file ]]; then
        log_message "ERROR" "Batch file not found or not readable"
        return 1
    }
    
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
    
    # Verify file size
    local line_count=$(wc -l < "$file")
    if ((line_count > MAX_BATCH_SIZE + 1)); then
        log_message "ERROR" "Batch file exceeds maximum size of $MAX_BATCH_SIZE entries"
        return 1
    fi
    
    return 0
}

function validate_batch_client_inputs() {
    local name=$1
    local ip=$2
    local allowed_ips=$3
    local dns=$4
    local keepalive=$5
    
    # Validate client name
    if ! [[ $name =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_message "ERROR" "Invalid client name format: $name"
        return 1
    fi
    
    # Validate IP if not auto
    if [[ $ip != "auto" ]]; then
        if ! validate_ip_address "$ip"; then
            log_message "ERROR" "Invalid IP address: $ip"
            return 1
        fi
    fi
    
    # Validate allowed IPs
    if ! validate_cidr_list "$allowed_ips"; then
        log_message "ERROR" "Invalid AllowedIPs format: $allowed_ips"
        return 1
    fi
    
    # Validate DNS servers
    if ! validate_dns_servers "$dns"; then
        log_message "ERROR" "Invalid DNS server format: $dns"
        return 1
    fi
    
    # Validate keepalive
    if ! [[ $keepalive =~ ^[0-9]+$ ]]; then
        log_message "ERROR" "Invalid keepalive value: $keepalive"
        return 1
    fi
    
    return 0
}

function create_batch_template() {
    local template_file="$TEMPLATE_DIR/batch_template.csv"
    
    mkdir -p "$TEMPLATE_DIR"
    
    # Create template with example data
    cat > "$template_file" << EOF
name,ip,allowed_ips,dns,keepalive
client1,auto,0.0.0.0/0,1.1.1.1,25
client2,10.0.0.2,192.168.1.0/24,8.8.8.8,30
client3,10.0.0.3,10.0.0.0/24;192.168.0.0/16,1.1.1.1;8.8.8.8,0
EOF
    
    log_message "SUCCESS" "Batch template created: $template_file"
    return 0
}

# Export functions
export -f process_batch_clients
export -f export_batch_configs
export -f import_batch_configs
export -f create_batch_template
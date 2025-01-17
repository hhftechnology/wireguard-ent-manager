#!/bin/bash

# Setup script for WireGuard Enterprise Features
# This script sets up the enterprise directory structure and installs components

set -e  # Exit on error

# Base directories
BASE_DIR=$(pwd)
ENTERPRISE_DIR="$BASE_DIR/enterprise"

echo "Setting up enterprise features in: $BASE_DIR"

# Create directory structure
echo "Creating directory structure..."
mkdir -p "$ENTERPRISE_DIR"/{web,monitoring,container,cloud,bridge,config/templates}
mkdir -p docs/enterprise

# Create Python virtual environment
echo "Setting up Python virtual environment..."
python3 -m venv "$ENTERPRISE_DIR/venv"
source "$ENTERPRISE_DIR/venv/bin/activate"

# Install Python dependencies
echo "Installing Python dependencies..."
pip install flask prometheus_client docker kubernetes \
    google-cloud-compute azure-identity azure-mgmt-compute \
    boto3 pyyaml

# Copy enterprise components
echo "Installing enterprise components..."

# Check if files exist before copying
if [ -f "wireguard_enterprise.py" ]; then
    cp wireguard_enterprise.py "$ENTERPRISE_DIR/"
    chmod 755 "$ENTERPRISE_DIR/wireguard_enterprise.py"
else
    echo "Error: wireguard_enterprise.py not found"
    exit 1
fi

# Create symbolic link for enterprise script
echo "Creating symbolic links..."
ln -sf "$ENTERPRISE_DIR/wireguard_enterprise.py" "wg-enterprise"

# Set up logging directory
echo "Setting up logging directory..."
sudo mkdir -p /var/log/wireguard
sudo chmod 755 /var/log/wireguard

echo "Enterprise setup completed successfully!"
echo "Use './wg-enterprise command' to manage enterprise features"
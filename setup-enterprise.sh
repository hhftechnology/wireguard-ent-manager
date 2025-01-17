#!/bin/bash

# Setup script for WireGuard Enterprise Features
# This script sets up the enterprise directory structure and installs components

set -e  # Exit on error

# Base directories
BASE_DIR="wireguard-ent-manager"
ENTERPRISE_DIR="$BASE_DIR/enterprise"
DOCS_DIR="$BASE_DIR/docs"

# Create directory structure
echo "Creating directory structure..."
mkdir -p "$ENTERPRISE_DIR"/{web,monitoring,container,cloud,config/templates}
mkdir -p "$DOCS_DIR/enterprise"

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

# Web Interface
cp enterprise/web/web_interface.py "$ENTERPRISE_DIR/web/"
chmod 644 "$ENTERPRISE_DIR/web/web_interface.py"

# Monitoring System
cp enterprise/monitoring/monitoring.py "$ENTERPRISE_DIR/monitoring/"
chmod 644 "$ENTERPRISE_DIR/monitoring/monitoring.py"

# Container Integration
cp enterprise/container/container_integration.py "$ENTERPRISE_DIR/container/"
chmod 644 "$ENTERPRISE_DIR/container/container_integration.py"

# Cloud Integration
cp enterprise/cloud/cloud_integration.py "$ENTERPRISE_DIR/cloud/"
chmod 644 "$ENTERPRISE_DIR/cloud/cloud_integration.py"

# Enterprise Integration
cp wireguard_enterprise.py "$ENTERPRISE_DIR/"
chmod 755 "$ENTERPRISE_DIR/wireguard_enterprise.py"

# Configuration
cp enterprise/config/enterprise-config.yaml "$ENTERPRISE_DIR/config/"
chmod 644 "$ENTERPRISE_DIR/config/enterprise-config.yaml"

# Create symbolic link for enterprise script
echo "Creating symbolic links..."
ln -sf "$ENTERPRISE_DIR/wireguard_enterprise.py" "$BASE_DIR/enterprise"

# Set up logging directory
echo "Setting up logging directory..."
sudo mkdir -p /var/log/wireguard
sudo chmod 755 /var/log/wireguard

# Update README.md with enterprise information
echo "Updating documentation..."
cat >> "$BASE_DIR/README.md" << 'EOF'

## Enterprise Features

This version includes additional enterprise-grade features:

- Web-based Management Interface
- Advanced Monitoring and Metrics
- Container Integration (Docker & Kubernetes)
- Cloud Provider Integration (AWS, GCP, Azure)

For detailed information about enterprise features, see docs/enterprise/.

### Enterprise Setup

1. Install enterprise components:
   ```bash
   ./setup-enterprise.sh
   ```

2. Configure enterprise features:
   ```bash
   cp enterprise/config/enterprise-config.yaml /etc/wireguard/enterprise-config.yaml
   ```

3. Start enterprise services:
   ```bash
   ./wg-enterprise start
   ```

For detailed configuration and usage instructions, see the enterprise documentation.
EOF

# Create enterprise documentation
echo "Creating enterprise documentation..."
for doc in web-interface monitoring container-integration cloud-integration enterprise-setup; do
    touch "$DOCS_DIR/enterprise/$doc.md"
done

echo "Enterprise setup completed successfully!"
echo "See $DOCS_DIR/enterprise/ for documentation."
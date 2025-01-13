#!/usr/bin/env python3

# WireGuard Web Interface Module (web_interface.py)
# Provides web-based management interface for WireGuard VPN
# Requires Flask and dependencies

from flask import Flask, render_template, request, jsonify
import subprocess
import os
import json
from functools import wraps
import logging
from datetime import datetime

app = Flask(__name__)

# Configuration
CONFIG_DIR = "/etc/wireguard"
LOG_DIR = "/var/log/wireguard"
API_PORT = 5000
API_HOST = "0.0.0.0"

# Security middleware
def require_api_key(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        api_key = request.headers.get('X-API-Key')
        if not api_key or api_key != os.getenv('WIREGUARD_API_KEY'):
            return jsonify({"error": "Unauthorized"}), 401
        return f(*args, **kwargs)
    return decorated

# API Routes
@app.route('/api/status', methods=['GET'])
@require_api_key
def get_status():
    """Get overall WireGuard status"""
    try:
        result = subprocess.run(['wg', 'show', 'all'], capture_output=True, text=True)
        return jsonify({"status": "success", "data": result.stdout})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)})

@app.route('/api/clients', methods=['GET'])
@require_api_key
def list_clients():
    """List all WireGuard clients"""
    try:
        result = subprocess.run(['bash', '-c', 'source /usr/local/bin/wireguard-enhanced.sh && list_clients'], 
                              capture_output=True, text=True)
        return jsonify({"status": "success", "data": result.stdout})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)})

@app.route('/api/clients', methods=['POST'])
@require_api_key
def create_client():
    """Create new WireGuard client"""
    try:
        data = request.get_json()
        cmd = ['bash', '-c', f'source /usr/local/bin/wireguard-enhanced.sh && create_client "{data["name"]}" "{data.get("tunnel", "wg0")}" "{data.get("ip", "auto")}"']
        result = subprocess.run(cmd, capture_output=True, text=True)
        return jsonify({"status": "success", "message": "Client created", "data": result.stdout})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)})

@app.route('/api/tunnels', methods=['GET'])
@require_api_key
def list_tunnels():
    """List all WireGuard tunnels"""
    try:
        result = subprocess.run(['bash', '-c', 'source /usr/local/bin/wireguard-enhanced.sh && list_tunnels'], 
                              capture_output=True, text=True)
        return jsonify({"status": "success", "data": result.stdout})
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)})

# Main application
def main():
    # Configure logging
    logging.basicConfig(
        filename=f"{LOG_DIR}/web_interface.log",
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )
    
    # Start Flask application
    app.run(host=API_HOST, port=API_PORT)

if __name__ == '__main__':
    main()
#!/usr/bin/env python3

# WireGuard Enterprise Integration (wireguard_enterprise.py)
# This is the main enterprise module that coordinates all enterprise features
# It provides a unified interface for managing web, monitoring, container, and cloud components

import os
import sys
import logging
import argparse
import threading
import signal
from typing import Dict, List
import json
import yaml

class WireGuardEnterprise:
    def __init__(self):
        self.logger = self._setup_logging()
        self.load_components()
    
    def _setup_logging(self):
        """Set up logging for the enterprise system"""
        logger = logging.getLogger('wireguard_enterprise')
        logger.setLevel(logging.INFO)
        
        # Create logs directory if it doesn't exist
        os.makedirs('/var/log/wireguard', exist_ok=True)
        
        handler = logging.FileHandler('/var/log/wireguard/enterprise.log')
        formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
        handler.setFormatter(formatter)
        logger.addHandler(handler)
        return logger
    
    def load_components(self):
        """Load all enterprise components"""
        try:
            # Import components only when needed to avoid startup errors
            self.logger.info("Enterprise system initialized")
        except Exception as e:
            self.logger.error(f"Error loading components: {str(e)}")
    
    def handle_web(self):
        """Handle web interface operations"""
        try:
            from enterprise.web.web_interface import app
            app.run(host='0.0.0.0', port=5000)
        except Exception as e:
            self.logger.error(f"Error starting web interface: {str(e)}")
            return False
    
    def handle_monitor(self):
        """Handle monitoring operations"""
        try:
            from enterprise.monitoring.monitoring import WireGuardMonitor
            monitor = WireGuardMonitor()
            monitor.run()
        except Exception as e:
            self.logger.error(f"Error starting monitoring: {str(e)}")
            return False
    
    def handle_container(self):
        """Handle container operations"""
        try:
            from enterprise.container.container_integration import WireGuardContainer
            container = WireGuardContainer()
            # List current containers
            containers = container.list_containers()
            print(json.dumps(containers, indent=2))
        except Exception as e:
            self.logger.error(f"Error in container operations: {str(e)}")
            return False
    
    def handle_cloud(self):
        """Handle cloud operations"""
        try:
            from enterprise.cloud.cloud_integration import WireGuardCloud
            cloud = WireGuardCloud()
            # Show cloud instances status
            for provider in ['aws', 'gcp', 'azure']:
                instances = cloud.list_instances(provider)
                if instances:
                    print(f"\n{provider.upper()} Instances:")
                    print(json.dumps(instances, indent=2))
        except Exception as e:
            self.logger.error(f"Error in cloud operations: {str(e)}")
            return False

def main():
    """Main entry point for the enterprise system"""
    parser = argparse.ArgumentParser(description='WireGuard Enterprise Management')
    parser.add_argument('command', choices=['web', 'monitor', 'container', 'cloud'],
                       help='Command to execute')
    
    args = parser.parse_args()
    enterprise = WireGuardEnterprise()
    
    # Handle interrupt signals gracefully
    def signal_handler(signum, frame):
        print("\nReceived shutdown signal. Stopping services...")
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Execute the requested command
    if args.command == 'web':
        enterprise.handle_web()
    elif args.command == 'monitor':
        enterprise.handle_monitor()
    elif args.command == 'container':
        enterprise.handle_container()
    elif args.command == 'cloud':
        enterprise.handle_cloud()

if __name__ == "__main__":
    main()
#!/usr/bin/env python3

# WireGuard Enterprise Integration (wireguard_enterprise.py)
# Main integration module that combines all enterprise features
# Provides unified management interface for all components

import os
import sys
import logging
import argparse
import threading
import signal
from typing import Dict, List
import json
import yaml

# Import our modules
from web_interface import app as web_app
from monitoring import WireGuardMonitor
from container_integration import WireGuardContainer
from cloud_integration import WireGuardCloud

class WireGuardEnterprise:
    def __init__(self):
        self.logger = self._setup_logging()
        self.monitor = WireGuardMonitor()
        self.container = WireGuardContainer()
        self.cloud = WireGuardCloud()
        self.threads = []
    
    def _setup_logging(self):
        """Configure logging for the enterprise system"""
        logger = logging.getLogger('wireguard_enterprise')
        logger.setLevel(logging.INFO)
        handler = logging.FileHandler('/var/log/wireguard/enterprise.log')
        formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
        handler.setFormatter(formatter)
        logger.addHandler(handler)
        return logger
    
    def start_services(self):
        """Start all enterprise services"""
        try:
            # Start monitoring in a separate thread
            monitor_thread = threading.Thread(target=self.monitor.run)
            monitor_thread.daemon = True
            monitor_thread.start()
            self.threads.append(monitor_thread)
            
            # Start web interface in a separate thread
            web_thread = threading.Thread(target=web_app.run, 
                                       kwargs={'host': '0.0.0.0', 'port': 5000})
            web_thread.daemon = True
            web_thread.start()
            self.threads.append(web_thread)
            
            self.logger.info("All enterprise services started successfully")
            return True
            
        except Exception as e:
            self.logger.error(f"Error starting services: {str(e)}")
            return False
    
    def stop_services(self):
        """Stop all enterprise services gracefully"""
        try:
            # Implement graceful shutdown
            for thread in self.threads:
                thread.join(timeout=5.0)
            
            self.logger.info("All enterprise services stopped successfully")
            return True
            
        except Exception as e:
            self.logger.error(f"Error stopping services: {str(e)}")
            return False
    
    def deploy_infrastructure(self, config_file: str) -> Dict:
        """Deploy WireGuard infrastructure based on configuration"""
        try:
            with open(config_file, 'r') as f:
                config = yaml.safe_load(f)
            
            results = {
                "cloud": [],
                "container": [],
                "status": "success"
            }
            
            # Deploy cloud instances if specified in config
            if 'cloud' in config:
                for cloud_config in config['cloud']:
                    provider = cloud_config['provider']
                    if provider == 'aws':
                        result = self.cloud.deploy_aws(cloud_config)
                    elif provider == 'gcp':
                        result = self.cloud.deploy_gcp(cloud_config)
                    elif provider == 'azure':
                        result = self.cloud.deploy_azure(cloud_config)
                    results['cloud'].append(result)
            
            # Deploy container instances if specified
            if 'containers' in config:
                for container_config in config['containers']:
                    platform = container_config['platform']
                    if platform == 'docker':
                        result = self.container.create_docker_container(
                            container_config['config_path'],
                            container_config['name']
                        )
                    elif platform == 'kubernetes':
                        result = self.container.create_k8s_deployment(
                            container_config['config_path'],
                            container_config['name'],
                            container_config.get('namespace', 'default')
                        )
                    results['container'].append(result)
            
            self.logger.info(f"Infrastructure deployment completed: {json.dumps(results)}")
            return results
            
        except Exception as e:
            self.logger.error(f"Error deploying infrastructure: {str(e)}")
            return {"status": "error", "message": str(e)}
    
    def get_system_status(self) -> Dict:
        """Get comprehensive system status across all components"""
        try:
            status = {
                "cloud_instances": {},
                "containers": [],
                "active_tunnels": 0,
                "connected_clients": 0,
                "monitoring_metrics": {},
                "system_health": {}
            }
            
            # Collect cloud instance status
            for provider in ['aws', 'gcp', 'azure']:
                instances = self.cloud.list_instances(provider)
                status['cloud_instances'][provider] = instances
            
            # Collect container status
            status['containers'] = self.container.list_containers()
            
            # Get WireGuard status using the core script
            with os.popen('bash -c "source /usr/local/bin/wireguard-enhanced.sh && list_tunnels"') as f:
                wireguard_status = f.read()
                status['active_tunnels'] = wireguard_status.count('active')
            
            # Get monitoring metrics
            status['monitoring_metrics'] = {
                "connections": ACTIVE_CONNECTIONS._value.get(),
                "bytes_transferred": {
                    "rx": BYTES_TRANSFERRED.labels(direction='rx')._value.get(),
                    "tx": BYTES_TRANSFERRED.labels(direction='tx')._value.get()
                }
            }
            
            # Get system health metrics
            status['system_health'] = {
                "cpu_usage": CPU_USAGE._value.get(),
                "memory_usage": MEMORY_USAGE._value.get()
            }
            
            return status
            
        except Exception as e:
            self.logger.error(f"Error getting system status: {str(e)}")
            return {"status": "error", "message": str(e)}
    
    def handle_cli(self):
        """Handle command line interface operations"""
        parser = argparse.ArgumentParser(description='WireGuard Enterprise Management')
        parser.add_argument('command', choices=['start', 'stop', 'status', 'deploy'])
        parser.add_argument('--config', help='Configuration file for deployment')
        
        args = parser.parse_args()
        
        if args.command == 'start':
            if self.start_services():
                print("Enterprise services started successfully")
                return 0
        elif args.command == 'stop':
            if self.stop_services():
                print("Enterprise services stopped successfully")
                return 0
        elif args.command == 'status':
            status = self.get_system_status()
            print(json.dumps(status, indent=2))
            return 0
        elif args.command == 'deploy':
            if not args.config:
                print("Error: --config required for deploy command")
                return 1
            result = self.deploy_infrastructure(args.config)
            print(json.dumps(result, indent=2))
            return 0 if result['status'] == 'success' else 1
        
        return 1

def main():
    """Main entry point for the enterprise system"""
    enterprise = WireGuardEnterprise()
    
    def signal_handler(signum, frame):
        print("\nReceived shutdown signal. Stopping services...")
        enterprise.stop_services()
        sys.exit(0)
    
    # Register signal handlers
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Handle CLI commands
    sys.exit(enterprise.handle_cli())

if __name__ == "__main__":
    main()
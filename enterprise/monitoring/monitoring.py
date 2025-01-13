#!/usr/bin/env python3

# WireGuard Monitoring System (monitoring.py)
# Provides advanced monitoring and metrics collection for WireGuard VPN
# Integrates with Prometheus and Grafana

import time
import subprocess
import json
from prometheus_client import start_http_server, Gauge, Counter
import psutil
import logging
from datetime import datetime

# Metrics configuration
METRICS_PORT = 9090
COLLECTION_INTERVAL = 30  # seconds

# Prometheus metrics
ACTIVE_CONNECTIONS = Gauge('wireguard_active_connections', 'Number of active WireGuard connections')
BYTES_TRANSFERRED = Counter('wireguard_bytes_transferred', 'Total bytes transferred', ['direction'])
HANDSHAKE_TIMES = Gauge('wireguard_last_handshake', 'Time since last handshake', ['peer'])
CPU_USAGE = Gauge('wireguard_cpu_usage', 'CPU usage percentage')
MEMORY_USAGE = Gauge('wireguard_memory_usage', 'Memory usage in bytes')

class WireGuardMonitor:
    def __init__(self):
        self.logger = self._setup_logging()
    
    def _setup_logging(self):
        """Configure logging"""
        logger = logging.getLogger('wireguard_monitor')
        logger.setLevel(logging.INFO)
        handler = logging.FileHandler('/var/log/wireguard/monitoring.log')
        formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
        handler.setFormatter(formatter)
        logger.addHandler(handler)
        return logger

    def collect_metrics(self):
        """Collect WireGuard metrics"""
        try:
            # Get WireGuard interface statistics
            result = subprocess.run(['wg', 'show', 'all', 'dump'], 
                                 capture_output=True, text=True)
            lines = result.stdout.strip().split('\n')
            
            active_peers = 0
            total_rx = 0
            total_tx = 0
            
            for line in lines:
                if line:
                    parts = line.split('\t')
                    if len(parts) >= 8:
                        active_peers += 1
                        total_rx += int(parts[5])
                        total_tx += int(parts[6])
                        HANDSHAKE_TIMES.labels(peer=parts[1]).set(
                            float(parts[4]) if parts[4] != '0' else float('inf')
                        )
            
            ACTIVE_CONNECTIONS.set(active_peers)
            BYTES_TRANSFERRED.labels(direction='rx').inc(total_rx)
            BYTES_TRANSFERRED.labels(direction='tx').inc(total_tx)
            
            # System metrics
            CPU_USAGE.set(psutil.cpu_percent())
            MEMORY_USAGE.set(psutil.Process().memory_info().rss)
            
            self.logger.info(f"Metrics collected: {active_peers} active peers")
            
        except Exception as e:
            self.logger.error(f"Error collecting metrics: {str(e)}")

    def run(self):
        """Start the monitoring system"""
        self.logger.info("Starting WireGuard monitoring system")
        start_http_server(METRICS_PORT)
        
        while True:
            self.collect_metrics()
            time.sleep(COLLECTION_INTERVAL)

def main():
    monitor = WireGuardMonitor()
    monitor.run()

if __name__ == '__main__':
    main()
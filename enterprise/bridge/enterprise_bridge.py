#!/usr/bin/env python3

# WireGuard Enterprise Bridge (enterprise_bridge.py)
# This module bridges the core bash scripts with enterprise Python modules

import os
import subprocess
import json
from typing import Dict, Any

class WireGuardBridge:
    def __init__(self):
        self.wg_script = "/usr/local/bin/wireguard-enhanced.sh"
    
    def execute_bash_command(self, command: str) -> Dict[str, Any]:
        """Execute a bash command and return the result"""
        try:
            result = subprocess.run(
                ['bash', '-c', f'source {self.wg_script} && {command}'],
                capture_output=True,
                text=True,
                check=True
            )
            return {"status": "success", "output": result.stdout}
        except subprocess.CalledProcessError as e:
            return {"status": "error", "message": e.stderr}

    def get_client_config(self, client_name: str) -> Dict[str, Any]:
        """Get client configuration for enterprise use"""
        result = self.execute_bash_command(f'cat /etc/wireguard/clients/{client_name}/wg0.conf')
        if result["status"] == "success":
            return {"status": "success", "config": result["output"]}
        return result

    def get_server_status(self) -> Dict[str, Any]:
        """Get server status for enterprise monitoring"""
        result = self.execute_bash_command('wg show all dump')
        if result["status"] == "success":
            # Parse the WireGuard status output
            lines = result["output"].strip().split('\n')
            status = {
                "interfaces": [],
                "peers": []
            }
            for line in lines:
                fields = line.split('\t')
                if len(fields) >= 8:
                    status["peers"].append({
                        "public_key": fields[1],
                        "endpoint": fields[3],
                        "allowed_ips": fields[4],
                        "latest_handshake": fields[5],
                        "transfer_rx": fields[6],
                        "transfer_tx": fields[7]
                    })
            return {"status": "success", "data": status}
        return result

    def create_client(self, client_name: str, config: Dict[str, Any]) -> Dict[str, Any]:
        """Create a new client with enterprise options"""
        command = f'create_client "{client_name}" "{config.get("tunnel", "wg0")}" '
        command += f'"{config.get("ip", "auto")}" "{config.get("allowed_ips", "0.0.0.0/0")}" '
        command += f'"{config.get("dns", "1.1.1.1")}" "{config.get("keepalive", "25")}"'
        
        return self.execute_bash_command(command)

    def remove_client(self, client_name: str) -> Dict[str, Any]:
        """Remove a client through enterprise interface"""
        return self.execute_bash_command(f'remove_client "{client_name}"')

    def update_server_config(self, config: Dict[str, Any]) -> Dict[str, Any]:
        """Update server configuration with enterprise settings"""
        # Generate new configuration file content
        config_content = self._generate_server_config(config)
        
        # Write to temporary file
        temp_file = "/tmp/wg0.conf.tmp"
        try:
            with open(temp_file, 'w') as f:
                f.write(config_content)
            
            # Move file to correct location
            result = self.execute_bash_command(f'mv {temp_file} /etc/wireguard/wg0.conf')
            if result["status"] == "success":
                # Restart WireGuard interface
                return self.execute_bash_command('systemctl restart wg-quick@wg0')
            return result
        except Exception as e:
            return {"status": "error", "message": str(e)}

    def _generate_server_config(self, config: Dict[str, Any]) -> str:
        """Generate WireGuard server configuration"""
        template = f"""[Interface]
PrivateKey = {config['private_key']}
Address = {config['address']}
ListenPort = {config.get('port', 51820)}
SaveConfig = true

# Enterprise configuration
PostUp = {config.get('post_up', '')}
PostDown = {config.get('post_down', '')}
"""
        return template

# This allows both direct Python imports and command-line usage
if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        bridge = WireGuardBridge()
        command = sys.argv[1]
        print(json.dumps(bridge.execute_bash_command(command), indent=2))
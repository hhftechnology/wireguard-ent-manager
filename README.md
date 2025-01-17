# Dont Use Enterprise feature still under development
# WireGuard Ent Manager (WGEM)

WGEM is a comprehensive management system for WireGuard VPN, designed to simplify the deployment, configuration, and maintenance of WireGuard servers in complex environments. This solution provides an interactive, feature-rich interface for managing multiple WireGuard tunnels, clients, and configurations through an easy-to-use command-line interface.

## Features

WGEM enhances the standard WireGuard experience with several advanced capabilities:

- Interactive menu-driven interface for easy management
- Support for multiple tunnel configurations
- Batch client creation and management
- Automatic peer cleanup and maintenance
- Full NAT configuration options (including Full Cone NAT for gaming)
- Comprehensive backup and restore functionality
- Detailed logging and monitoring
- Multiple VPN modes (proxy and point-to-point)
- Flexible DNS configuration options
- Advanced firewall integration

## System Requirements

### Compatible Operating Systems

WGEM has been thoroughly tested and is officially supported on the following Linux distributions:

Primary Support:
- Ubuntu 20.04 LTS and newer
- Debian 11 (Bullseye) and newer
- Fedora 35 and newer
- CentOS Stream 8 and newer
- Rocky Linux 8 and newer
- AlmaLinux 8 and newer

Secondary Support:
- Arch Linux (rolling release)
- Oracle Linux 8 and newer

### Minimum System Requirements

- CPU: 1 core (2 recommended)
- RAM: 512MB (1GB recommended)
- Storage: 1GB free space
- Network: Static IP address or stable DDNS setup
- Root access or sudo privileges

## Installation

### Quick Start

1. Clone the repository:
```bash
git clone https://github.com/hhftechnology/wireguard-ent-manager.git
cd wireguard-ent-manager
```

2. Make the scripts executable:
```bash
chmod +x *.sh
```

3. Run the installation script as root:
```bash
sudo ./wireguard-enhanced.sh
```

### Manual Installation

If you prefer to set up components individually:

1. Install required dependencies:
```bash
# For Ubuntu/Debian
sudo apt update
sudo apt install wireguard iptables qrencode

# For Fedora
sudo dnf install wireguard-tools iptables qrencode

# For CentOS/Rocky/Alma
sudo dnf install epel-release
sudo dnf install wireguard-tools iptables qrencode
```

2. Set up the configuration directory:
```bash
sudo mkdir -p /etc/wireguard
sudo chmod 700 /etc/wireguard
```

3. Run the script:
```bash
sudo ./wireguard-enhanced.sh
```

## Configuration

### Initial Setup

When you first run WGEM, you'll be guided through several configuration steps:

1. VPN Mode Selection
   - Proxy Mode: Routes all client traffic through the VPN
   - Point-to-Point Mode: Routes only specified networks

2. DNS Configuration
   - System DNS
   - Custom DNS servers
   - Split DNS options

3. Network Configuration
   - Interface selection
   - IP range allocation
   - Port selection

### Managing Clients

WGEM provides several ways to manage clients:

1. Individual Client Creation:
```bash
Select: "Client Management" > "Create New Client"
```

2. Batch Client Creation:
```bash
Select: "Client Management" > "Batch Create Clients"
```

Example batch file format (clients.csv):
```csv
client_name,ip_address,allowed_ips,keepalive,dns
client1,10.0.0.2,0.0.0.0/0,25,1.1.1.1
client2,10.0.0.3,192.168.1.0/24,,8.8.8.8
```

### Advanced Configuration

#### NAT Configuration

For gaming or applications requiring specific NAT types:
```bash
Select: "System Configuration" > "Configure NAT Settings"
```

#### Multiple Tunnels

To create additional tunnels:
```bash
Select: "Tunnel Management" > "Create New Tunnel"
```

## Maintenance

### Regular Maintenance Tasks

1. Cleaning Inactive Peers:
```bash
Select: "Monitoring & Maintenance" > "Clean Inactive Peers"
```

2. Backing Up Configurations:
```bash
Select: "Backup & Restore" > "Create Backup"
```

### Monitoring

Monitor your WireGuard installation:
```bash
Select: "Monitoring & Maintenance" > "Show System Status"
```

## Troubleshooting

### Common Issues

1. Permission Errors
   - Ensure you're running the script as root
   - Check directory permissions: /etc/wireguard should be 700

2. Network Connectivity
   - Verify firewall rules
   - Check port forwarding
   - Validate IP configurations

3. Client Connection Issues
   - Verify client configurations
   - Check DNS settings
   - Validate AllowedIPs settings

### Logging

View system logs:
```bash
Select: "Monitoring & Maintenance" > "View Logs"
```

## Contributing

We welcome contributions! Please read our contributing guidelines before submitting pull requests.

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## Security Considerations

WGEM implements several security best practices:

- Secure key generation and storage
- Proper permission management
- Regular security updates
- Automated peer cleanup
- Detailed activity logging

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

WGEM is based on the WireGuard VPN project and includes improvements suggested by the community. Special thanks to all contributors who have helped make this project better.

## Support

For support, please:

1. Check the documentation
2. Search existing issues on the [forum](https://forum.hhf.technology/).
3. Create a new issue if needed on the [forum](https://forum.hhf.technology/).

## Roadmap

Future planned features include:

- Web interface for management
- Multi-server synchronization
- Advanced monitoring and metrics
- Container integration
- Cloud provider integration

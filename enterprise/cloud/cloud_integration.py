#!/usr/bin/env python3

# WireGuard Cloud Provider Integration Module (cloud_integration.py)
# Provides cloud provider support for WireGuard VPN
# Supports AWS, GCP, and Azure integration

import boto3
import google.cloud.compute_v1 as compute_engine
from azure.identity import DefaultAzureCredential
from azure.mgmt.compute import ComputeManagementClient
import logging
import json
from typing import Dict, List, Optional
import os

class WireGuardCloud:
    def __init__(self):
        self.logger = self._setup_logging()
        self._init_cloud_clients()
    
    def _setup_logging(self):
        """Configure logging for cloud operations"""
        logger = logging.getLogger('wireguard_cloud')
        logger.setLevel(logging.INFO)
        handler = logging.FileHandler('/var/log/wireguard/cloud.log')
        formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
        handler.setFormatter(formatter)
        logger.addHandler(handler)
        return logger
    
    def _init_cloud_clients(self):
        """Initialize cloud provider clients"""
        try:
            # AWS client initialization
            self.ec2_client = boto3.client('ec2')
            
            # GCP client initialization
            self.gcp_client = compute_engine.InstancesClient()
            
            # Azure client initialization
            credential = DefaultAzureCredential()
            subscription_id = os.getenv('AZURE_SUBSCRIPTION_ID')
            self.azure_client = ComputeManagementClient(credential, subscription_id)
            
        except Exception as e:
            self.logger.error(f"Error initializing cloud clients: {str(e)}")
    
    def deploy_aws(self, config: Dict) -> Dict:
        """Deploy WireGuard instance on AWS"""
        try:
            # Create security group for WireGuard
            security_group = self.ec2_client.create_security_group(
                GroupName=f"wireguard-{config['name']}",
                Description='WireGuard VPN Security Group'
            )
            
            # Configure security group rules
            self.ec2_client.authorize_security_group_ingress(
                GroupId=security_group['GroupId'],
                IpPermissions=[
                    {
                        'IpProtocol': 'udp',
                        'FromPort': 51820,
                        'ToPort': 51820,
                        'IpRanges': [{'CidrIp': '0.0.0.0/0'}]
                    }
                ]
            )
            
            # Create EC2 instance with WireGuard
            user_data = self._generate_user_data(config)
            instance = self.ec2_client.run_instances(
                ImageId=config['ami_id'],
                InstanceType=config.get('instance_type', 't2.micro'),
                MinCount=1,
                MaxCount=1,
                SecurityGroupIds=[security_group['GroupId']],
                UserData=user_data,
                TagSpecifications=[{
                    'ResourceType': 'instance',
                    'Tags': [{'Key': 'Name', 'Value': f"wireguard-{config['name']}"}]
                }]
            )
            
            self.logger.info(f"Created AWS instance: {instance['Instances'][0]['InstanceId']}")
            return {
                "status": "success",
                "provider": "aws",
                "instance_id": instance['Instances'][0]['InstanceId']
            }
            
        except Exception as e:
            self.logger.error(f"AWS deployment error: {str(e)}")
            return {"status": "error", "message": str(e)}
    
    def deploy_gcp(self, config: Dict) -> Dict:
        """Deploy WireGuard instance on Google Cloud Platform"""
        try:
            instance_client = compute_engine.InstancesClient()
            
            # Prepare instance configuration
            instance = {
                "name": f"wireguard-{config['name']}",
                "machine_type": f"zones/{config['zone']}/machineTypes/{config.get('machine_type', 'e2-micro')}",
                "disks": [{
                    "boot": True,
                    "auto_delete": True,
                    "initialize_params": {
                        "source_image": config['image'],
                    }
                }],
                "network_interfaces": [{
                    "network": "global/networks/default",
                    "access_configs": [{"name": "External NAT"}]
                }],
                "metadata": {
                    "items": [{
                        "key": "startup-script",
                        "value": self._generate_user_data(config)
                    }]
                }
            }
            
            # Create the instance
            operation = instance_client.insert(
                project=config['project_id'],
                zone=config['zone'],
                instance_resource=instance
            )
            operation.result()  # Wait for completion
            
            self.logger.info(f"Created GCP instance: wireguard-{config['name']}")
            return {
                "status": "success",
                "provider": "gcp",
                "instance_name": f"wireguard-{config['name']}"
            }
            
        except Exception as e:
            self.logger.error(f"GCP deployment error: {str(e)}")
            return {"status": "error", "message": str(e)}
    
    def deploy_azure(self, config: Dict) -> Dict:
        """Deploy WireGuard instance on Azure"""
        try:
            # Create network security group
            nsg_params = {
                'location': config['location'],
                'security_rules': [{
                    'name': 'wireguard',
                    'protocol': 'Udp',
                    'source_address_prefix': '*',
                    'destination_address_prefix': '*',
                    'source_port_range': '*',
                    'destination_port_range': '51820',
                    'access': 'Allow',
                    'priority': 100,
                    'direction': 'Inbound'
                }]
            }
            
            # Create VM parameters
            vm_parameters = {
                'location': config['location'],
                'os_profile': {
                    'computer_name': f"wireguard-{config['name']}",
                    'admin_username': config['admin_username'],
                    'custom_data': self._generate_user_data(config)
                },
                'hardware_profile': {
                    'vm_size': config.get('vm_size', 'Standard_B1s')
                },
                'storage_profile': {
                    'image_reference': {
                        'publisher': 'Canonical',
                        'offer': 'UbuntuServer',
                        'sku': '18.04-LTS',
                        'version': 'latest'
                    }
                },
                'network_profile': {
                    'network_interfaces': [{
                        'id': config['network_interface_id']
                    }]
                }
            }
            
            # Create the VM
            poller = self.azure_client.virtual_machines.begin_create_or_update(
                config['resource_group'],
                f"wireguard-{config['name']}",
                vm_parameters
            )
            vm = poller.result()
            
            self.logger.info(f"Created Azure VM: {vm.name}")
            return {
                "status": "success",
                "provider": "azure",
                "vm_name": vm.name
            }
            
        except Exception as e:
            self.logger.error(f"Azure deployment error: {str(e)}")
            return {"status": "error", "message": str(e)}
    
    def _generate_user_data(self, config: Dict) -> str:
        """Generate cloud-init user data for WireGuard installation"""
        user_data = """#!/bin/bash
apt-get update
apt-get install -y wireguard

# Configure WireGuard
{wireguard_config}

# Enable IP forwarding
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p

# Start WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0
""".format(wireguard_config=config.get('wireguard_config', ''))
        
        return user_data
    
    def list_instances(self, provider: str) -> List[Dict]:
        """List all WireGuard instances across cloud providers"""
        instances = []
        
        try:
            if provider == "aws":
                response = self.ec2_client.describe_instances(
                    Filters=[{'Name': 'tag:Name', 'Values': ['wireguard-*']}]
                )
                for reservation in response['Reservations']:
                    for instance in reservation['Instances']:
                        instances.append({
                            'provider': 'aws',
                            'id': instance['InstanceId'],
                            'state': instance['State']['Name'],
                            'public_ip': instance.get('PublicIpAddress', 'N/A')
                        })
                        
            elif provider == "gcp":
                project_id = os.getenv('GCP_PROJECT_ID')
                zone = os.getenv('GCP_ZONE')
                instance_list = self.gcp_client.list(project=project_id, zone=zone)
                for instance in instance_list:
                    if instance.name.startswith('wireguard-'):
                        instances.append({
                            'provider': 'gcp',
                            'id': instance.name,
                            'state': instance.status,
                            'public_ip': instance.network_interfaces[0].access_configs[0].nat_ip
                        })
                        
            elif provider == "azure":
                resource_group = os.getenv('AZURE_RESOURCE_GROUP')
                vms = self.azure_client.virtual_machines.list(resource_group)
                for vm in vms:
                    if vm.name.startswith('wireguard-'):
                        instances.append({
                            'provider': 'azure',
                            'id': vm.name,
                            'state': vm.provisioning_state,
                            'public_ip': 'N/A'  # Need separate call to get public IP
                        })
                        
        except Exception as e:
            self.logger.error(f"Error listing instances for {provider}: {str(e)}")
        
        return instances
    
    def terminate_instance(self, provider: str, instance_id: str) -> Dict:
        """Terminate a WireGuard instance"""
        try:
            if provider == "aws":
                self.ec2_client.terminate_instances(InstanceIds=[instance_id])
                
            elif provider == "gcp":
                project_id = os.getenv('GCP_PROJECT_ID')
                zone = os.getenv('GCP_ZONE')
                operation = self.gcp_client.delete(
                    project=project_id,
                    zone=zone,
                    instance=instance_id
                )
                operation.result()
                
            elif provider == "azure":
                resource_group = os.getenv('AZURE_RESOURCE_GROUP')
                self.azure_client.virtual_machines.begin_delete(
                    resource_group,
                    instance_id
                ).result()
            
            self.logger.info(f"Terminated {provider} instance: {instance_id}")
            return {"status": "success", "message": f"Instance {instance_id} terminated"}
            
        except Exception as e:
            self.logger.error(f"Error terminating instance: {str(e)}")
            return {"status": "error", "message": str(e)}

def main():
    """Main function for testing cloud integration"""
    cloud = WireGuardCloud()
    # Add test configuration and deployment here if needed

if __name__ == "__main__":
    main()
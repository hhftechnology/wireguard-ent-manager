#!/usr/bin/env python3

# WireGuard Container Integration Module (container_integration.py)
# Provides container support for WireGuard VPN
# Supports Docker and Kubernetes integration

import docker
import yaml
import os
import logging
from kubernetes import client, config
from typing import Dict, List
import time

class WireGuardContainer:
    def __init__(self):
        self.logger = self._setup_logging()
        self.docker_client = docker.from_env()
        
        # Try to load kubernetes config if available
        try:
            config.load_kube_config()
            self.k8s_client = client.CoreV1Api()
            self.k8s_available = True
        except:
            self.k8s_available = False
    
    def _setup_logging(self):
        """Configure logging"""
        logger = logging.getLogger('wireguard_container')
        logger.setLevel(logging.INFO)
        handler = logging.FileHandler('/var/log/wireguard/container.log')
        formatter = logging.Formatter('%(asctime)s - %(levelname)s - %(message)s')
        handler.setFormatter(formatter)
        logger.addHandler(handler)
        return logger

    def create_docker_container(self, config_path: str, name: str) -> Dict:
        """Create a Docker container running WireGuard"""
        try:
            # Validate configuration file
            if not os.path.exists(config_path):
                raise FileNotFoundError(f"Configuration file not found: {config_path}")
            
            # Create container with enhanced security options
            container = self.docker_client.containers.run(
                'linuxserver/wireguard:latest',
                name=name,
                cap_add=['NET_ADMIN', 'SYS_MODULE'],
                volumes={
                    config_path: {'bind': '/config', 'mode': 'rw'},
                    '/lib/modules': {'bind': '/lib/modules', 'mode': 'ro'}
                },
                sysctls={
                    'net.ipv4.conf.all.src_valid_mark': '1',
                    'net.ipv4.ip_forward': '1'
                },
                restart_policy={"Name": "unless-stopped"},
                detach=True,
                privileged=False,  # Enhanced security
                network_mode="host",  # Required for WireGuard
                environment={
                    "PUID": "1000",
                    "PGID": "1000",
                    "TZ": "Etc/UTC"
                }
            )
            
            # Wait for container to be running
            for _ in range(30):  # 30-second timeout
                container.reload()
                if container.status == 'running':
                    break
                time.sleep(1)
            
            if container.status != 'running':
                raise RuntimeError("Container failed to start properly")
            
            self.logger.info(f"Created Docker container: {name}")
            return {
                "status": "success",
                "container_id": container.id,
                "name": name,
                "status": container.status
            }
            
        except Exception as e:
            self.logger.error(f"Error creating Docker container: {str(e)}")
            return {"status": "error", "message": str(e)}

    def create_k8s_deployment(self, config_path: str, name: str, namespace: str) -> Dict:
        """Create a Kubernetes deployment for WireGuard"""
        if not self.k8s_available:
            return {"status": "error", "message": "Kubernetes not configured"}
        
        try:
            # Validate configuration file
            if not os.path.exists(config_path):
                raise FileNotFoundError(f"Configuration file not found: {config_path}")
            
            # Create namespace if it doesn't exist
            try:
                self.k8s_client.create_namespace(
                    client.V1Namespace(metadata=client.V1ObjectMeta(name=namespace))
                )
            except client.rest.ApiException as e:
                if e.status != 409:  # Ignore if namespace already exists
                    raise
            
            # Enhanced deployment configuration
            deployment = {
                "apiVersion": "apps/v1",
                "kind": "Deployment",
                "metadata": {
                    "name": name,
                    "namespace": namespace,
                    "labels": {"app": name}
                },
                "spec": {
                    "replicas": 1,
                    "selector": {
                        "matchLabels": {"app": name}
                    },
                    "template": {
                        "metadata": {
                            "labels": {"app": name}
                        },
                        "spec": {
                            "containers": [{
                                "name": name,
                                "image": "linuxserver/wireguard:latest",
                                "securityContext": {
                                    "capabilities": {
                                        "add": ["NET_ADMIN", "SYS_MODULE"]
                                    },
                                    "privileged": False,
                                    "runAsNonRoot": True,
                                    "runAsUser": 1000,
                                    "runAsGroup": 1000
                                },
                                "volumeMounts": [{
                                    "name": "config",
                                    "mountPath": "/config",
                                    "readOnly": True
                                }],
                                "resources": {
                                    "requests": {
                                        "memory": "128Mi",
                                        "cpu": "100m"
                                    },
                                    "limits": {
                                        "memory": "256Mi",
                                        "cpu": "200m"
                                    }
                                },
                                "livenessProbe": {
                                    "exec": {
                                        "command": [
                                            "wg",
                                            "show"
                                        ]
                                    },
                                    "initialDelaySeconds": 30,
                                    "periodSeconds": 60
                                }
                            }],
                            "volumes": [{
                                "name": "config",
                                "configMap": {
                                    "name": f"{name}-config"
                                }
                            }]
                        }
                    }
                }
            }
            
            # Create ConfigMap for WireGuard configuration
            with open(config_path, 'r') as f:
                config_data = f.read()
            
            config_map = client.V1ConfigMap(
                metadata=client.V1ObjectMeta(
                    name=f"{name}-config",
                    namespace=namespace
                ),
                data={"wg0.conf": config_data}
            )
            
            # Create or update ConfigMap
            try:
                self.k8s_client.create_namespaced_config_map(namespace, config_map)
            except client.rest.ApiException as e:
                if e.status == 409:
                    self.k8s_client.replace_namespaced_config_map(
                        f"{name}-config",
                        namespace,
                        config_map
                    )
                else:
                    raise
            
            # Create the deployment
            apps_v1 = client.AppsV1Api()
            apps_v1.create_namespaced_deployment(namespace, deployment)
            
            # Wait for deployment to be ready
            for _ in range(60):  # 60-second timeout
                response = apps_v1.read_namespaced_deployment_status(name, namespace)
                if response.status.ready_replicas == 1:
                    break
                time.sleep(1)
            
            self.logger.info(f"Created Kubernetes deployment: {name} in namespace {namespace}")
            return {
                "status": "success",
                "deployment": name,
                "namespace": namespace
            }
            
        except Exception as e:
            self.logger.error(f"Error creating Kubernetes deployment: {str(e)}")
            return {"status": "error", "message": str(e)}

    def list_containers(self) -> List[Dict]:
        """List all WireGuard containers"""
        containers = []
        
        # List Docker containers
        try:
            docker_containers = self.docker_client.containers.list(
                filters={"ancestor": "linuxserver/wireguard"}
            )
            for container in docker_containers:
                # Get container stats
                stats = container.stats(stream=False)
                containers.append({
                    "type": "docker",
                    "id": container.id,
                    "name": container.name,
                    "status": container.status,
                    "created": container.attrs['Created'],
                    "ip_address": container.attrs['NetworkSettings']['IPAddress'],
                    "ports": container.attrs['NetworkSettings']['Ports'],
                    "memory_usage": stats['memory_stats'].get('usage', 0),
                    "cpu_usage": stats['cpu_stats'].get('cpu_usage', {}).get('total_usage', 0)
                })
        except Exception as e:
            self.logger.error(f"Error listing Docker containers: {str(e)}")
        
        # List Kubernetes pods if available
        if self.k8s_available:
            try:
                pods = self.k8s_client.list_pod_for_all_namespaces(
                    label_selector="app=wireguard"
                )
                for pod in pods.items:
                    # Get pod metrics if available
                    try:
                        metrics = client.CustomObjectsApi().list_cluster_custom_object(
                            'metrics.k8s.io',
                            'v1beta1',
                            'pods',
                            field_selector=f"metadata.name={pod.metadata.name}"
                        )
                        pod_metrics = metrics['items'][0] if metrics['items'] else {}
                    except:
                        pod_metrics = {}
                    
                    containers.append({
                        "type": "kubernetes",
                        "id": pod.metadata.uid,
                        "name": pod.metadata.name,
                        "namespace": pod.metadata.namespace,
                        "status": pod.status.phase,
                        "ip": pod.status.pod_ip,
                        "node": pod.spec.node_name,
                        "created": pod.metadata.creation_timestamp,
                        "resources": pod_metrics.get('usage', {})
                    })
            except Exception as e:
                self.logger.error(f"Error listing Kubernetes pods: {str(e)}")
        
        return containers

    def remove_container(self, container_id: str, container_type: str) -> Dict:
        """Remove a WireGuard container"""
        try:
            if container_type == "docker":
                container = self.docker_client.containers.get(container_id)
                
                # Stop container gracefully first
                container.stop(timeout=30)
                
                # Remove container and its volumes
                container.remove(force=True, v=True)
                
                self.logger.info(f"Removed Docker container: {container_id}")
                return {"status": "success", "message": "Container removed successfully"}
                
            elif container_type == "kubernetes" and self.k8s_available:
                # Remove deployment and associated resources
                apps_v1 = client.AppsV1Api()
                
                # Get pod information
                pod = self.k8s_client.read_namespaced_pod(container_id)
                namespace = pod.metadata.namespace
                deployment_name = pod.metadata.owner_references[0].name
                
                # Delete deployment
                apps_v1.delete_namespaced_deployment(
                    deployment_name,
                    namespace
                )
                
                # Delete ConfigMap
                try:
                    self.k8s_client.delete_namespaced_config_map(
                        f"{deployment_name}-config",
                        namespace
                    )
                except client.rest.ApiException:
                    pass  # Ignore if ConfigMap doesn't exist
                
                self.logger.info(f"Removed Kubernetes deployment and associated resources: {container_id}")
                return {"status": "success", "message": "Kubernetes resources removed successfully"}
                
            else:
                raise ValueError(f"Invalid container type: {container_type}")
                
        except Exception as e:
            error_msg = f"Error removing {container_type} container: {str(e)}"
            self.logger.error(error_msg)
            return {"status": "error", "message": error_msg}
    
    def get_container_logs(self, container_id: str, container_type: str, lines: int = 100) -> Dict:
        """Get container logs"""
        try:
            if container_type == "docker":
                container = self.docker_client.containers.get(container_id)
                logs = container.logs(tail=lines, timestamps=True).decode('utf-8')
                return {"status": "success", "logs": logs}
                
            elif container_type == "kubernetes" and self.k8s_available:
                logs = self.k8s_client.read_namespaced_pod_log(
                    container_id,
                    namespace=self.k8s_client.read_namespaced_pod(container_id).metadata.namespace,
                    tail_lines=lines,
                    timestamps=True
                )
                return {"status": "success", "logs": logs}
                
            else:
                raise ValueError(f"Invalid container type: {container_type}")
                
        except Exception as e:
            error_msg = f"Error getting logs for {container_type} container: {str(e)}"
            self.logger.error(error_msg)
            return {"status": "error", "message": error_msg}

def main():
    """Main function for testing container integration"""
    container_manager = WireGuardContainer()
    
    # Example usage
    if os.getenv('WIREGUARD_TEST_CONTAINER'):
        test_config = "/etc/wireguard/test/wg0.conf"
        result = container_manager.create_docker_container(test_config, "wireguard-test")
        print(f"Test container creation result: {result}")
        
        containers = container_manager.list_containers()
        print(f"Active containers: {containers}")

if __name__ == "__main__":
    main()
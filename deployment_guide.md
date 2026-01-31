# Deployment Guide - K8s Cluster with Ansible Controller

## Architecture Overview

This setup now includes **4 VMs**:

```
┌─────────────────────────────────────────────────────────┐
│                    Host Machine                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │              VirtualBox VMs                      │   │
│  │                                                   │   │
│  │  ┌──────────────────┐                           │   │
│  │  │ansible-controller│  Manages cluster via SSH   │   │
│  │  │ 192.168.56.5     │                           │   │
│  │  │ 1 CPU, 1GB RAM   │                           │   │
│  │  └────────┬─────────┘                           │   │
│  │           │ SSH                                  │   │
│  │           ▼                                      │   │
│  │  ┌──────────────┐  ┌──────────┐  ┌──────────┐ │   │
│  │  │ k8s-master   │  │ worker-1 │  │ worker-2 │ │   │
│  │  │192.168.56.10 │  │   .11    │  │   .12    │ │   │
│  │  │2 CPU, 2GB RAM│  │2 CPU, 2GB│  │2 CPU, 2GB│ │   │
│  │  └──────────────┘  └──────────┘  └──────────┘ │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### VM Details

| VM | IP | Role | Resources |
|----|-----|------|-----------|
| ansible-controller | 192.168.56.5 | Ansible control node | 1 CPU, 1GB RAM |
| k8s-master | 192.168.56.10 | K8s control plane | 2 CPU, 2GB RAM |
| k8s-worker-1 | 192.168.56.11 | K8s worker | 2 CPU, 2GB RAM |
| k8s-worker-2 | 192.168.56.12 | K8s worker | 2 CPU, 2GB RAM |

**Total Resources**: 7 CPUs, 7GB RAM

## Benefits of Separate Ansible Controller

✅ **Realistic setup**: Mimics real-world where Ansible runs from separate bastion/jump host  
✅ **Clean separation**: Control plane only runs Kubernetes, not management tools  
✅ **Learning**: Practice proper Ansible remote execution patterns  
✅ **Reusable**: Controller can manage multiple clusters  
✅ **No local Ansible needed**: Ansible runs inside the VM, not on your host  

## Quick Start

### Option 1: Automated Setup (Recommended)

```bash
# Make script executable
chmod +x setup.sh

# Run complete setup
./setup.sh

# This will:
# 1. Start all 4 VMs
# 2. Configure SSH keys
# 3. Copy project files to controller
# 4. Deploy K8s cluster from controller
# 5. Deploy application
```

### Option 2: Manual Step-by-Step

#### Step 1: Start VMs

```bash
vagrant up

# Verify all 4 VMs are running
vagrant status
```

#### Step 2: Setup SSH Keys

```bash
# Setup SSH access from controller to K8s nodes
make setup-ssh

# Or manually:
# Get public key from controller
PUB_KEY=$(vagrant ssh ansible-controller -c "cat /home/vagrant/.ssh/id_rsa.pub")

# Add to each K8s node
echo "$PUB_KEY" | vagrant ssh k8s-master -c "cat >> /home/vagrant/.ssh/authorized_keys"
echo "$PUB_KEY" | vagrant ssh k8s-worker-1 -c "cat >> /home/vagrant/.ssh/authorized_keys"
echo "$PUB_KEY" | vagrant ssh k8s-worker-2 -c "cat >> /home/vagrant/.ssh/authorized_keys"
```

#### Step 3: Copy Project Files to Controller

```bash
make copy-project

# Or manually:
vagrant ssh ansible-controller -c "mkdir -p /home/vagrant/k8s-project"
tar czf - ansible k8s | vagrant ssh ansible-controller -c "cd /home/vagrant/k8s-project && tar xzf -"
```

#### Step 4: Test Ansible Connectivity

```bash
make test-ansible

# Or manually:
vagrant ssh ansible-controller
cd /home/vagrant/k8s-project/ansible
ansible all -i inventory/hosts.ini -m ping
```

Expected output:
```
k8s-master | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
k8s-worker-1 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
k8s-worker-2 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

#### Step 5: Deploy Kubernetes Cluster

```bash
# From host machine
make deploy-cluster

# Or run playbooks from controller:
vagrant ssh ansible-controller
cd /home/vagrant/k8s-project/ansible

ansible-playbook -i inventory/hosts.ini playbooks/00-prerequisites.yml
ansible-playbook -i inventory/hosts.ini playbooks/01-install-crio.yml
ansible-playbook -i inventory/hosts.ini playbooks/02-install-kubernetes.yml
ansible-playbook -i inventory/hosts.ini playbooks/03-init-control-plane.yml
ansible-playbook -i inventory/hosts.ini playbooks/04-join-workers.yml
ansible-playbook -i inventory/hosts.ini playbooks/05-deploy-applications.yml
```

#### Step 6: Verify Cluster

```bash
# SSH into master
vagrant ssh k8s-master

# Check nodes
kubectl get nodes
# All 3 nodes should be Ready

# Check pods
kubectl get pods -A

# Check Traefik LoadBalancer
kubectl get svc traefik -n kube-system
```

#### Step 7: Install Storage Provisioner

```bash
vagrant ssh k8s-master

kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml

# Verify
kubectl get storageclass
```

#### Step 8: Build and Deploy Application

```bash
# On host machine
cd app
go mod tidy
cd ..

# Build image
docker build -t myapp:latest ./app

# Save and distribute
docker save myapp:latest | gzip > myapp.tar.gz
vagrant scp myapp.tar.gz k8s-master:/tmp/
vagrant scp myapp.tar.gz k8s-worker-1:/tmp/
vagrant scp myapp.tar.gz k8s-worker-2:/tmp/

# Load on each node
vagrant ssh k8s-master -c "sudo ctr -n k8s.io images import /tmp/myapp.tar.gz"
vagrant ssh k8s-worker-1 -c "sudo ctr -n k8s.io images import /tmp/myapp.tar.gz"
vagrant ssh k8s-worker-2 -c "sudo ctr -n k8s.io images import /tmp/myapp.tar.gz"

# Deploy application
vagrant ssh k8s-master
kubectl apply -f /home/vagrant/k8s/namespace.yaml
kubectl apply -f /home/vagrant/k8s/postgres/
kubectl apply -f /home/vagrant/k8s/redis/
sleep 20
kubectl apply -f /home/vagrant/k8s/app/
```

## Working with the Ansible Controller

### SSH into Controller

```bash
vagrant ssh ansible-controller
```

### Run Ansible Commands

```bash
# From controller
cd /home/vagrant/k8s-project/ansible

# Ping all nodes
ansible all -i inventory/hosts.ini -m ping

# Check uptime
ansible all -i inventory/hosts.ini -m command -a "uptime"

# Gather facts
ansible k8s-master -i inventory/hosts.ini -m setup

# Run ad-hoc commands
ansible all -i inventory/hosts.ini -a "df -h"

# Check K8s version on all nodes
ansible k8s_cluster -i inventory/hosts.ini -a "kubectl version --client"
```

### Run Specific Playbooks

```bash
# From controller
cd /home/vagrant/k8s-project/ansible

# Re-run just prerequisites
ansible-playbook -i inventory/hosts.ini playbooks/00-prerequisites.yml

# Check mode (dry-run)
ansible-playbook -i inventory/hosts.ini playbooks/00-prerequisites.yml --check

# Verbose output
ansible-playbook -i inventory/hosts.ini playbooks/00-prerequisites.yml -vvv

# Run on specific hosts
ansible-playbook -i inventory/hosts.ini playbooks/00-prerequisites.yml --limit k8s-master
```

### Create Custom Playbooks

```bash
# From controller
cd /home/vagrant/k8s-project/ansible

# Create new playbook
cat > playbooks/custom-check.yml <<'EOF'
---
- name: Custom health check
  hosts: k8s_cluster
  tasks:
    - name: Check disk space
      command: df -h /
      register: disk_space
    
    - name: Display disk space
      debug:
        var: disk_space.stdout_lines
    
    - name: Check memory
      command: free -h
      register: memory
    
    - name: Display memory
      debug:
        var: memory.stdout_lines
EOF

# Run it
ansible-playbook -i inventory/hosts.ini playbooks/custom-check.yml
```

## SSH Access Patterns

```bash
# From host → Controller
vagrant ssh ansible-controller

# From host → K8s master
vagrant ssh k8s-master

# From host → Worker
vagrant ssh k8s-worker-1

# From controller → K8s master (once SSH keys are set up)
vagrant ssh ansible-controller
ssh vagrant@192.168.56.10

# From controller → Worker
ssh vagrant@192.168.56.11
```

## Accessing Services

### Application

```bash
# Get LoadBalancer IP
TRAEFIK_IP=$(vagrant ssh k8s-master -c "kubectl get svc traefik -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}'" 2>/dev/null | tr -d '\r')

# Test endpoints
curl http://${TRAEFIK_IP}/health
curl http://${TRAEFIK_IP}/ready

# Login
curl -X POST http://${TRAEFIK_IP}/login \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","password":"password123"}'
```

### Monitoring

```bash
# Port-forward from host (need kubectl configured to access k8s-master)
# Option 1: Configure kubectl on host
vagrant ssh k8s-master -c "cat /home/vagrant/.kube/config" > ~/.kube/config-vagrant
export KUBECONFIG=~/.kube/config-vagrant

kubectl port-forward -n monitoring svc/grafana 3000:3000
# Access http://localhost:3000

# Option 2: Port-forward from master
vagrant ssh k8s-master
kubectl port-forward -n monitoring svc/grafana 3000:3000 --address=0.0.0.0
# Access http://192.168.56.10:3000 from host
```

## Troubleshooting

### SSH Key Issues

```bash
# Re-generate SSH keys on controller
vagrant ssh ansible-controller
rm -f /home/vagrant/.ssh/id_rsa*
ssh-keygen -t rsa -b 2048 -f /home/vagrant/.ssh/id_rsa -N ""
exit

# Re-run setup
make setup-ssh
```

### Ansible Connection Issues

```bash
# From controller, check SSH manually
vagrant ssh ansible-controller
ssh -v vagrant@192.168.56.10

# Check authorized_keys on master
vagrant ssh k8s-master
cat /home/vagrant/.ssh/authorized_keys

# Check SSH service
sudo systemctl status sshd
```

### Project Files Not on Controller

```bash
# Re-copy project files
make copy-project

# Verify
vagrant ssh ansible-controller
ls -la /home/vagrant/k8s-project/
```

### Playbook Fails

```bash
# Run with verbose output
vagrant ssh ansible-controller
cd /home/vagrant/k8s-project/ansible
ansible-playbook -i inventory/hosts.ini playbooks/00-prerequisites.yml -vvv

# Check specific host
ansible k8s-master -i inventory/hosts.ini -m ping -vvv
```

## Useful Ansible Controller Commands

```bash
# Check all nodes status
ansible all -i inventory/hosts.ini -m shell -a "hostname && uptime"

# Check K8s pods on master
ansible control_plane -i inventory/hosts.ini -m shell -a "kubectl get pods -A"

# Check CRI-O on all nodes
ansible k8s_cluster -i inventory/hosts.ini -m shell -a "sudo systemctl status crio"

# Reboot all workers (carefully!)
ansible workers -i inventory/hosts.ini -m reboot

# Check available disk space
ansible all -i inventory/hosts.ini -m shell -a "df -h /"

# Check memory usage
ansible all -i inventory/hosts.ini -m shell -a "free -h"
```

## Cleanup

```bash
# Destroy all VMs
vagrant destroy -f

# Or destroy specific VM
vagrant destroy ansible-controller -f
vagrant destroy k8s-master -f

# Clean up Docker images on host
docker rmi myapp:latest

# Clean up temporary files
rm -f myapp.tar.gz
```

## Next Steps

1. **Practice Ansible**: Create custom playbooks for cluster management
2. **Add Monitoring to Controller**: Install Ansible Tower/AWX
3. **Inventory Management**: Use dynamic inventory for cloud providers
4. **Secrets Management**: Integrate Ansible Vault for sensitive data
5. **CI/CD Integration**: Trigger Ansible from Jenkins/GitLab
6. **Multi-Cluster**: Use controller to manage multiple K8s clusters
7. **Backup Automation**: Create playbooks for cluster backups
8. **Rolling Updates**: Practice rolling updates via Ansible

## Benefits You're Learning

✅ **Infrastructure as Code**: Everything defined in playbooks  
✅ **Idempotency**: Run playbooks multiple times safely  
✅ **Configuration Management**: Centralized control  
✅ **Remote Execution**: Execute on multiple nodes  
✅ **Real-World Patterns**: Bastion/jump host architecture  
✅ **Troubleshooting**: Debug remote systems  
✅ **Automation**: Repeatable deployments  

This setup teaches you production-ready practices! 🚀
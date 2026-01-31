#!/bin/bash
# setup.sh - Quick setup script for K8s Golang Cluster with Ansible Controller

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing=0
    
    if ! command -v vagrant &> /dev/null; then
        log_error "Vagrant not found. Please install Vagrant."
        missing=1
    fi
    
    if ! command -v vboxmanage &> /dev/null; then
        log_error "VirtualBox not found. Please install VirtualBox."
        missing=1
    fi
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker."
        missing=1
    fi
    
    if [ $missing -eq 1 ]; then
        exit 1
    fi
    
    log_info "All prerequisites satisfied!"
}

setup_vms() {
    log_step "Starting VMs with Vagrant..."
    log_info "This will create 4 VMs:"
    log_info "  - ansible-controller (192.168.56.5) - 1 CPU, 1GB RAM"
    log_info "  - k8s-master (192.168.56.10) - 2 CPU, 2GB RAM"
    log_info "  - k8s-worker-1 (192.168.56.11) - 2 CPU, 2GB RAM"
    log_info "  - k8s-worker-2 (192.168.56.12) - 2 CPU, 2GB RAM"
    
    vagrant up
    
    log_info "Waiting for VMs to be ready..."
    sleep 10
}

setup_ssh_keys() {
    log_step "Setting up SSH keys from Ansible controller to K8s nodes..."
    
    # Get public key from controller
    log_info "Retrieving SSH public key from controller..."
    PUB_KEY=$(vagrant ssh ansible-controller -c "cat /home/vagrant/.ssh/id_rsa.pub" 2>/dev/null)
    
    # Distribute to all K8s nodes
    log_info "Distributing SSH key to k8s-master..."
    echo "$PUB_KEY" | vagrant ssh k8s-master -c "cat >> /home/vagrant/.ssh/authorized_keys && chmod 600 /home/vagrant/.ssh/authorized_keys"
    
    log_info "Distributing SSH key to k8s-worker-1..."
    echo "$PUB_KEY" | vagrant ssh k8s-worker-1 -c "cat >> /home/vagrant/.ssh/authorized_keys && chmod 600 /home/vagrant/.ssh/authorized_keys"
    
    log_info "Distributing SSH key to k8s-worker-2..."
    echo "$PUB_KEY" | vagrant ssh k8s-worker-2 -c "cat >> /home/vagrant/.ssh/authorized_keys && chmod 600 /home/vagrant/.ssh/authorized_keys"
    
    # Test connectivity
    log_info "Testing SSH connectivity from controller..."
    vagrant ssh ansible-controller -c "ssh -o StrictHostKeyChecking=no vagrant@192.168.56.10 'hostname'" || true
    vagrant ssh ansible-controller -c "ssh -o StrictHostKeyChecking=no vagrant@192.168.56.11 'hostname'" || true
    vagrant ssh ansible-controller -c "ssh -o StrictHostKeyChecking=no vagrant@192.168.56.12 'hostname'" || true
    
    log_info "SSH keys configured successfully!"
}

copy_project_files() {
    log_step "Copying project files to Ansible controller..."
    
    vagrant ssh ansible-controller -c "mkdir -p /home/vagrant/k8s-project"
    
    log_info "Copying ansible directory..."
    tar czf - ansible | vagrant ssh ansible-controller -c "cd /home/vagrant/k8s-project && tar xzf -"
    
    log_info "Copying k8s manifests..."
    tar czf - k8s | vagrant ssh ansible-controller -c "cd /home/vagrant/k8s-project && tar xzf -"
    
    log_info "Project files copied successfully!"
}

test_ansible_connectivity() {
    log_step "Testing Ansible connectivity..."
    
    vagrant ssh ansible-controller -c "cd /home/vagrant/k8s-project/ansible && ansible all -i inventory/hosts.ini -m ping"
    
    log_info "Ansible connectivity verified!"
}

deploy_k8s() {
    log_step "Deploying Kubernetes cluster from Ansible controller..."
    
    log_info "Running prerequisites playbook..."
    vagrant ssh ansible-controller -c "cd /home/vagrant/k8s-project/ansible && ansible-playbook -i inventory/hosts.ini playbooks/00-prerequisites.yml"
    
    log_info "Installing CRI-O..."
    vagrant ssh ansible-controller -c "cd /home/vagrant/k8s-project/ansible && ansible-playbook -i inventory/hosts.ini playbooks/01-install-crio.yml"
    
    log_info "Installing Kubernetes..."
    vagrant ssh ansible-controller -c "cd /home/vagrant/k8s-project/ansible && ansible-playbook -i inventory/hosts.ini playbooks/02-install-kubernetes.yml"
    
    log_info "Initializing control plane..."
    vagrant ssh ansible-controller -c "cd /home/vagrant/k8s-project/ansible && ansible-playbook -i inventory/hosts.ini playbooks/03-init-control-plane.yml"
    
    log_info "Joining worker nodes..."
    vagrant ssh ansible-controller -c "cd /home/vagrant/k8s-project/ansible && ansible-playbook -i inventory/hosts.ini playbooks/04-join-workers.yml"
    
    log_info "Deploying core applications (MetalLB, Traefik, Monitoring)..."
    vagrant ssh ansible-controller -c "cd /home/vagrant/k8s-project/ansible && ansible-playbook -i inventory/hosts.ini playbooks/05-deploy-applications.yml"
    
    log_info "Kubernetes cluster deployed successfully!"
}

install_local_path_provisioner() {
    log_step "Installing local-path-provisioner for persistent storage..."
    
    vagrant ssh k8s-master -c "kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.24/deploy/local-path-storage.yaml"
    
    log_info "Waiting for local-path-provisioner to be ready..."
    sleep 15
}

build_and_deploy_app() {
    log_step "Building application..."
    
    cd app
    go mod tidy
    cd ..
    
    docker build -t myapp:latest ./app
    
    log_info "Saving Docker image..."
    docker save myapp:latest | gzip > myapp.tar.gz
    
    log_info "Copying image to nodes..."
    vagrant scp myapp.tar.gz k8s-master:/tmp/
    vagrant scp myapp.tar.gz k8s-worker-1:/tmp/
    vagrant scp myapp.tar.gz k8s-worker-2:/tmp/
    
    log_info "Loading image on control plane..."
    vagrant ssh k8s-master -c "sudo ctr -n k8s.io images import /tmp/myapp.tar.gz"
    
    log_info "Loading image on worker-1..."
    vagrant ssh k8s-worker-1 -c "sudo ctr -n k8s.io images import /tmp/myapp.tar.gz"
    
    log_info "Loading image on worker-2..."
    vagrant ssh k8s-worker-2 -c "sudo ctr -n k8s.io images import /tmp/myapp.tar.gz"
    
    log_info "Deploying application to Kubernetes..."
    vagrant ssh k8s-master -c "kubectl apply -f /home/vagrant/k8s/namespace.yaml"
    vagrant ssh k8s-master -c "kubectl apply -f /home/vagrant/k8s/postgres/"
    vagrant ssh k8s-master -c "kubectl apply -f /home/vagrant/k8s/redis/"
    
    log_info "Waiting for database to be ready..."
    sleep 30
    
    vagrant ssh k8s-master -c "kubectl apply -f /home/vagrant/k8s/app/"
    
    rm -f myapp.tar.gz
}

display_info() {
    log_info "Deployment complete!"
    echo ""
    echo "=========================================="
    echo "Cluster Information"
    echo "=========================================="
    
    TRAEFIK_IP=$(vagrant ssh k8s-master -c "kubectl get svc traefik -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}'" 2>/dev/null | tr -d '\r')
    
    echo ""
    echo "VM Access:"
    echo "  Ansible Controller: vagrant ssh ansible-controller"
    echo "  K8s Master:         vagrant ssh k8s-master"
    echo "  Worker 1:           vagrant ssh k8s-worker-1"
    echo "  Worker 2:           vagrant ssh k8s-worker-2"
    echo ""
    echo "Application URL: http://${TRAEFIK_IP}"
    echo ""
    echo "Test the application:"
    echo "  curl http://${TRAEFIK_IP}/health"
    echo "  curl http://${TRAEFIK_IP}/ready"
    echo ""
    echo "Login:"
    echo "  curl -X POST http://${TRAEFIK_IP}/login \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"username\":\"testuser\",\"password\":\"password123\"}'"
    echo ""
    echo "Access Grafana (from host):"
    echo "  kubectl port-forward -n monitoring svc/grafana 3000:3000"
    echo "  http://localhost:3000 (admin/admin)"
    echo ""
    echo "Access Prometheus (from host):"
    echo "  kubectl port-forward -n monitoring svc/prometheus 9090:9090"
    echo "  http://localhost:9090"
    echo ""
    echo "Run Ansible commands from controller:"
    echo "  vagrant ssh ansible-controller"
    echo "  cd /home/vagrant/k8s-project/ansible"
    echo "  ansible all -i inventory/hosts.ini -m ping"
    echo ""
    echo "View cluster status:"
    echo "  vagrant ssh k8s-master"
    echo "  kubectl get nodes"
    echo "  kubectl get pods -A"
    echo "=========================================="
}

main() {
    echo "=========================================="
    echo "K8s Golang Cluster Setup"
    echo "with Ansible Controller Node"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    
    if [ "$1" == "clean" ]; then
        log_warn "Destroying existing VMs..."
        vagrant destroy -f
        log_info "Cleanup complete!"
        exit 0
    fi
    
    setup_vms
    setup_ssh_keys
    copy_project_files
    test_ansible_connectivity
    deploy_k8s
    install_local_path_provisioner
    build_and_deploy_app
    
    log_info "Waiting for all pods to be ready..."
    sleep 30
    
    display_info
}

# Run main function
main "$@"
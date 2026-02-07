.PHONY: help build push deploy-cluster deploy-app clean ssh-controller ssh-master ssh-worker-1 ssh-worker-2 destroy setup-ssh

# Variables
APP_NAME := myapp
VERSION := latest
REGISTRY := localhost:5000
IMAGE := $(REGISTRY)/$(APP_NAME):$(VERSION)

help:
	@echo "Available targets:"
	@echo "  setup-ssh       - Setup SSH keys from controller to K8s nodes"
	@echo "  build           - Build Docker image"
	@echo "  push            - Push Docker image to registry"
	@echo "  deploy-cluster  - Deploy Kubernetes cluster with Ansible (from controller)"
	@echo "  deploy-app      - Deploy application to Kubernetes"
	@echo "  clean           - Clean up built artifacts"
	@echo "  destroy         - Destroy Vagrant VMs"
	@echo "  ssh-controller  - SSH into Ansible controller"
	@echo "  ssh-master      - SSH into control plane"
	@echo "  ssh-worker-1    - SSH into worker 1"
	@echo "  ssh-worker-2    - SSH into worker 2"

# Setup SSH keys from controller to K8s nodes
setup-ssh:
	@echo "Setting up SSH keys from Ansible controller to K8s nodes..."
	@echo "Copying SSH public key from controller..."
	@PUB_KEY=$$(vagrant ssh ansible-controller -c "cat /home/vagrant/.ssh/id_rsa.pub" 2>/dev/null); \
	echo "$$PUB_KEY" | vagrant ssh k8s-master -c "cat >> /home/vagrant/.ssh/authorized_keys && chmod 600 /home/vagrant/.ssh/authorized_keys"; \
	echo "$$PUB_KEY" | vagrant ssh k8s-worker-1 -c "cat >> /home/vagrant/.ssh/authorized_keys && chmod 600 /home/vagrant/.ssh/authorized_keys"; \
	echo "$$PUB_KEY" | vagrant ssh k8s-worker-2 -c "cat >> /home/vagrant/.ssh/authorized_keys && chmod 600 /home/vagrant/.ssh/authorized_keys"
	@echo "Testing SSH connectivity from controller..."
	@vagrant ssh ansible-controller -c "ssh -o StrictHostKeyChecking=no vagrant@192.168.56.10 'hostname'" || true
	@vagrant ssh ansible-controller -c "ssh -o StrictHostKeyChecking=no vagrant@192.168.56.11 'hostname'" || true
	@vagrant ssh ansible-controller -c "ssh -o StrictHostKeyChecking=no vagrant@192.168.56.12 'hostname'" || true
	@echo "SSH setup complete!"

# Copy project files to Ansible controller
copy-project:
	@echo "Copying project files to Ansible controller..."
	@vagrant ssh ansible-controller -c "mkdir -p /home/vagrant/k8s-project"
	@tar czf - ansible k8s | vagrant ssh ansible-controller -c "cd /home/vagrant/k8s-project && tar xzf -"
	@echo "Project files copied!"

# Build the Go application Docker image
build:
	@echo "Building Docker image..."
	cd app && docker build -t $(APP_NAME):$(VERSION) .
	@echo "Image built: $(APP_NAME):$(VERSION)"

# Load image to nodes using skopeo (pre-installed on VMs)
load-image: build
	@echo "Saving image to tarball..."
	@docker save $(APP_NAME):$(VERSION) | gzip > $(APP_NAME).tar.gz
	@echo "Copying to nodes..."
	@vagrant scp $(APP_NAME).tar.gz k8s-master:/tmp/
	@vagrant scp $(APP_NAME).tar.gz k8s-worker-1:/tmp/
	@vagrant scp $(APP_NAME).tar.gz k8s-worker-2:/tmp/
	@echo "Loading image on nodes with skopeo..."
	@vagrant ssh k8s-master -c "sudo skopeo copy docker-archive:/tmp/$(APP_NAME).tar.gz containers-storage:localhost/$(APP_NAME):$(VERSION)"
	@vagrant ssh k8s-worker-1 -c "sudo skopeo copy docker-archive:/tmp/$(APP_NAME).tar.gz containers-storage:localhost/$(APP_NAME):$(VERSION)"
	@vagrant ssh k8s-worker-2 -c "sudo skopeo copy docker-archive:/tmp/$(APP_NAME).tar.gz containers-storage:localhost/$(APP_NAME):$(VERSION)"
	@echo "Verifying images..."
	@vagrant ssh k8s-master -c "sudo crictl images | grep $(APP_NAME)"
	@rm -f $(APP_NAME).tar.gz
	@echo "Image loaded successfully on all nodes!"

# Deploy Kubernetes cluster using Ansible FROM the controller node
deploy-cluster: copy-project setup-ssh
	@echo "Deploying Kubernetes cluster from Ansible controller..."
	@vagrant ssh ansible-controller -c "cd /home/vagrant/k8s-project/ansible && ansible-playbook -i inventory/hosts.ini playbooks/00-prerequisites.yml"
	@vagrant ssh ansible-controller -c "cd /home/vagrant/k8s-project/ansible && ansible-playbook -i inventory/hosts.ini playbooks/01-install-crio.yml"
	@vagrant ssh ansible-controller -c "cd /home/vagrant/k8s-project/ansible && ansible-playbook -i inventory/hosts.ini playbooks/02-install-kubernetes.yml"
	@vagrant ssh ansible-controller -c "cd /home/vagrant/k8s-project/ansible && ansible-playbook -i inventory/hosts.ini playbooks/03-init-control-plane.yml"
	@vagrant ssh ansible-controller -c "cd /home/vagrant/k8s-project/ansible && ansible-playbook -i inventory/hosts.ini playbooks/04-join-workers.yml"
	@echo "Waiting for cluster to be ready..."
	@sleep 30
	@vagrant ssh ansible-controller -c "cd /home/vagrant/k8s-project/ansible && ansible-playbook -i inventory/hosts.ini playbooks/05-deploy-applications.yml"
	@echo "Cluster deployed successfully!"

# Deploy application to Kubernetes
deploy-app:
	@echo "Deploying application..."
	kubectl apply -f k8s/namespace.yaml
	kubectl apply -f k8s/postgres/
	kubectl apply -f k8s/redis/
	@echo "Waiting for database to be ready..."
	@sleep 20
	kubectl apply -f k8s/app/
	@echo "Application deployed successfully!"
	@echo ""
	@echo "Get Traefik LoadBalancer IP:"
	@echo "  kubectl get svc traefik -n kube-system"

# Clean built artifacts
clean:
	@echo "Cleaning up..."
	docker rmi -f $(APP_NAME):$(VERSION) 2>/dev/null || true
	docker rmi -f $(IMAGE) 2>/dev/null || true

# Destroy Vagrant VMs
destroy:
	@echo "Destroying Vagrant VMs..."
	vagrant destroy -f

# SSH into nodes
ssh-controller:
	vagrant ssh ansible-controller

ssh-master:
	vagrant ssh k8s-master

ssh-worker-1:
	vagrant ssh k8s-worker-1

ssh-worker-2:
	vagrant ssh k8s-worker-2

# Quick deployment (VMs + Cluster + App)
all: build
	@echo "Starting complete deployment..."
	vagrant up
	@sleep 10
	$(MAKE) deploy-cluster
	$(MAKE) deploy-app
	@echo ""
	@echo "Deployment complete!"
	@echo "Get service endpoints:"
	@echo "  kubectl get svc -A"

# Test Ansible connectivity from controller
test-ansible:
	@echo "Testing Ansible connectivity from controller..."
	vagrant ssh ansible-controller -c "cd /home/vagrant/k8s-project/ansible && ansible all -i inventory/hosts.ini -m ping"
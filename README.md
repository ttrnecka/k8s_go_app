# Kubernetes Cluster Project - Complete Setup

## Project Structure

```
k8s-golang-cluster/
├── Vagrantfile
├── Makefile
├── ansible/
│   ├── inventory/
│   │   └── hosts.ini
│   ├── playbooks/
│   │   ├── 00-prerequisites.yml
│   │   ├── 01-install-crio.yml
│   │   ├── 02-install-kubernetes.yml
│   │   ├── 03-init-control-plane.yml
│   │   ├── 04-join-workers.yml
│   │   └── 05-deploy-applications.yml
│   ├── roles/
│   │   ├── common/
│   │   │   └── tasks/
│   │   │       └── main.yml
│   │   ├── crio/
│   │   │   └── tasks/
│   │   │       └── main.yml
│   │   ├── kubernetes/
│   │   │   └── tasks/
│   │   │       └── main.yml
│   │   ├── control-plane/
│   │   │   └── tasks/
│   │   │       └── main.yml
│   │   └── worker/
│   │       └── tasks/
│   │           └── main.yml
│   └── ansible.cfg
├── app/
│   ├── main.go
│   ├── handlers/
│   │   ├── auth.go
│   │   └── post.go
│   ├── db/
│   │   └── postgres.go
│   ├── session/
│   │   └── redis.go
│   ├── middleware/
│   │   └── auth.go
│   ├── metrics/
│   │   └── prometheus.go
│   ├── go.mod
│   ├── go.sum
│   └── Dockerfile
├── k8s/
│   ├── namespace.yaml
│   ├── metallb/
│   │   ├── metallb-namespace.yaml
│   │   ├── metallb-install.yaml
│   │   └── ipaddresspool.yaml
│   ├── traefik/
│   │   ├── traefik-rbac.yaml
│   │   ├── traefik-deployment.yaml
│   │   ├── traefik-service.yaml
│   │   └── traefik-ingressroute.yaml
│   ├── postgres/
│   │   ├── postgres-secret.yaml
│   │   ├── postgres-pvc.yaml
│   │   ├── postgres-statefulset.yaml
│   │   └── postgres-service.yaml
│   ├── redis/
│   │   ├── redis-deployment.yaml
│   │   └── redis-service.yaml
│   ├── app/
│   │   ├── app-secret.yaml
│   │   ├── app-deployment.yaml
│   │   ├── app-service.yaml
│   │   └── app-ingress.yaml
│   └── monitoring/
│       ├── prometheus-rbac.yaml
│       ├── prometheus-config.yaml
│       ├── prometheus-deployment.yaml
│       ├── prometheus-service.yaml
│       ├── grafana-config.yaml
│       ├── grafana-deployment.yaml
│       └── grafana-service.yaml
└── README.md
```

## Quick Start

```bash
# 1. Clone and navigate to project
cd k8s-golang-cluster

# 2. Start VMs with Vagrant
vagrant up

# 3. Deploy Kubernetes cluster with Ansible
make deploy-cluster

# 4. Build and deploy application
make build
make deploy-app

# 5. Access the application
# Get LoadBalancer IP
kubectl get svc -n kube-system traefik

# Access app at http://<LOADBALANCER-IP>/
```

## Components Overview

### Infrastructure
- **3 VirtualBox VMs**: 1 control plane (k8s-master), 2 workers (k8s-worker-1, k8s-worker-2)
- **OS**: Ubuntu 22.04
- **Network**: Private network 192.168.56.0/24

### Kubernetes Stack
- **Distribution**: kubeadm
- **Runtime**: CRI-O
- **CNI**: Calico
- **Ingress**: Traefik with MetalLB LoadBalancer

### Application Stack
- **Frontend**: Golang (net/http)
- **Database**: PostgreSQL (StatefulSet with persistent storage)
- **Cache/Session**: Redis
- **Monitoring**: Prometheus + Grafana

### Golang Application Features
- `/health` - Liveness probe
- `/ready` - Readiness probe
- `/metrics` - Prometheus metrics
- `/login` (POST) - User login
- `/logout` (POST) - User logout
- `/post` (POST) - Create text post (authenticated)
- `/posts` (GET) - List posts (authenticated)

## Detailed Setup Instructions

### Prerequisites
- VirtualBox installed
- Vagrant installed
- Ansible installed (>= 2.9)
- Make installed
- Docker installed (for building app image)

### Network Configuration
- Control Plane: 192.168.56.10
- Worker 1: 192.168.56.11
- Worker 2: 192.168.56.12
- MetalLB IP Pool: 192.168.56.100-192.168.56.110

### Makefile Targets

```bash
make build          # Build Docker image
make push           # Push image to registry (configure registry first)
make deploy-cluster # Deploy K8s cluster via Ansible
make deploy-app     # Deploy application to K8s
make clean          # Destroy VMs
make ssh-master     # SSH into control plane
make ssh-worker-1   # SSH into worker 1
make ssh-worker-2   # SSH into worker 2
```

### Accessing Services

**Application**:
```bash
TRAEFIK_IP=$(kubectl get svc traefik -n kube-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://$TRAEFIK_IP/health

kubectl -n kube-system port-forward svc/traefik 8080:8080 --address 0.0.0.0
```

alternatively on Windows provided:
TRAEFIK_IP = 192.168.56.100
k8s-master IP = 192.168.56.10

```
route add 192.168.56.100 mask 255.255.255.255 192.168.56.10
```

**Grafana**:
```bash
kubectl port-forward -n monitoring svc/grafana 3000:3000 --address 0.0.0.0
# Access at http://localhost:3000 (admin/admin)
```

**Prometheus**:
```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090 --address 0.0.0.0
# Access at http://localhost:9090
```

## Database Schema

PostgreSQL tables:
- `users` (id, username, password_hash, created_at)
- `posts` (id, user_id, content, created_at)

## Session Management

Sessions stored in Redis with structure:
```
session:<session_id> -> {user_id, username, created_at}
```

## Monitoring

**Prometheus Metrics**:
- HTTP request duration
- HTTP request count by endpoint and status
- Active sessions count
- Database connection pool stats

**Grafana Dashboards**:
- Application metrics
- Kubernetes cluster overview
- Node metrics

## Blue-Green Deployment

The application uses labels for blue-green deployments:
```bash
# Switch to green deployment
kubectl patch service myapp -n app -p '{"spec":{"selector":{"version":"green"}}}'

# Switch to blue deployment
kubectl patch service myapp -n app -p '{"spec":{"selector":{"version":"blue"}}}'
```

## Troubleshooting

**VMs not starting**:
```bash
vagrant destroy -f
vagrant up
```

**Ansible fails**:
```bash
# Check connectivity
ansible all -i ansible/inventory/hosts.ini -m ping

# Run with verbose
ansible-playbook -i ansible/inventory/hosts.ini ansible/playbooks/00-prerequisites.yml -vvv
```

**Application not accessible**:
```bash
# Check pods
kubectl get pods -n app

# Check ingress
kubectl get ingress -n app

# Check Traefik
kubectl logs -n kube-system -l app=traefik
```

## Next Steps

1. Customize the Golang application
2. Add more endpoints
3. Implement proper password hashing (bcrypt)
4. Add rate limiting
5. Configure SSL/TLS with cert-manager
6. Set up proper backup strategies for PostgreSQL

## License

MIT

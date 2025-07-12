# KOF Quick Start Guide

Get KOF up and running in 15 minutes! This guide covers three deployment scenarios to help you get started quickly.

## 📋 Prerequisites

Before starting, ensure you have:

- **Kubernetes cluster** (1.19+) with admin access
- **Helm** 3.0+ installed
- **kubectl** configured for your cluster
- **Docker** (for local development)
- **Git** for cloning repositories

### System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **CPU** | 2 cores | 4+ cores |
| **Memory** | 4 GB | 8+ GB |
| **Storage** | 25 GB | 50+ GB |
| **Nodes** | 1 | 3+ |

## 🚀 Option 1: Local Development (Fastest)

Perfect for development, testing, and learning KOF.

### Step 1: Setup KCM

```bash
# Clone and setup KCM (required dependency)
git clone https://github.com/k0rdent/kcm.git
cd kcm
make cli-install
make dev-apply
```

### Step 2: Setup KOF

```bash
# Clone KOF in a separate directory
cd ..
git clone https://github.com/k0rdent/kof.git
cd kof

# Install tools and setup local registry
make cli-install
make registry-deploy
make helm-push
```

### Step 3: Deploy KOF Components

```bash
# Deploy in order (dependencies matter)
make dev-operators-deploy    # CRDs and operators
make dev-ms-deploy          # Mothership (UI and management)
make dev-storage-deploy     # Storage backend
make dev-collectors-deploy  # Data collectors
```

### Step 4: Access the UI

```bash
# Port forward to access Grafana
kubectl port-forward svc/grafana-vm-service 3000:3000 -n kof

# Get admin credentials
kubectl get secret grafana-admin-credentials -n kof -o jsonpath='{.data.GF_SECURITY_ADMIN_USER}' | base64 -d
kubectl get secret grafana-admin-credentials -n kof -o jsonpath='{.data.GF_SECURITY_ADMIN_PASSWORD}' | base64 -d
```

Open http://localhost:3000 and login with the credentials above.

### Step 5: Explore KOF Operator UI

```bash
# Port forward to access KOF operator UI
kubectl port-forward svc/kof-mothership-kof-operator-ui 9090:9090 -n kof
```

Open http://localhost:9090 to see Prometheus targets and collector metrics.

## 🌐 Option 2: Single Cluster Production

Deploy all KOF components to a single production cluster.

### Step 1: Install Dependencies

```bash
# Install cert-manager for TLS
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.4/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager -n cert-manager
```

### Step 2: Configure Values

```bash
# Create production values file
cat > production-values.yaml <<EOF
global:
  clusterName: production
  storageClass: "your-storage-class"

grafana:
  ingress:
    enabled: true
    host: grafana.yourdomain.com
  security:
    create_secret: true

victoriametrics:
  enabled: true
  vmcluster:
    enabled: true
    replicationFactor: 2
    replicaCount: 2

cert-manager:
  enabled: true
  email: admin@yourdomain.com

dex:
  enabled: true
  config:
    issuer: https://dex.yourdomain.com
    staticClients:
      - id: grafana
        name: Grafana
        secret: your-secure-secret
        redirectURIs:
          - https://grafana.yourdomain.com/login/generic_oauth
EOF
```

### Step 3: Deploy KOF

```bash
# Add KOF Helm repository
helm repo add kof oci://ghcr.io/k0rdent/kof/charts
helm repo update

# Install KOF components
helm install kof-mothership kof/kof-mothership -n kof --create-namespace -f production-values.yaml
helm install kof-storage kof/kof-storage -n kof -f production-values.yaml
helm install kof-collectors kof/kof-collectors -n kof
```

### Step 4: Configure DNS

Point your domains to the cluster ingress:

```bash
# Get ingress IP
kubectl get ingress -n kof
```

Create DNS records:
- `grafana.yourdomain.com` → Ingress IP
- `dex.yourdomain.com` → Ingress IP

## 🏢 Option 3: Multi-Cluster Production

Deploy KOF across multiple clusters for production scale.

### Architecture Overview

```
[Mothership] ──► [Regional Cluster] ──► [Child Cluster 1]
     │                 │                      │
     │                 │                [Child Cluster 2]
     │                 │                      │
     └─── Management   └─── Storage     └─── Workloads
```

### Step 1: Mothership Cluster

```bash
# Install on management cluster
helm install kof-mothership kof/kof-mothership -n kof --create-namespace \
  --set kcm.installTemplates=true \
  --set grafana.enabled=true \
  --set grafana.ingress.enabled=true \
  --set grafana.ingress.host=grafana.yourdomain.com
```

### Step 2: Regional Cluster

```bash
# Install on storage cluster
kubectl label cluster regional-cluster k0rdent.mirantis.com/kof-cluster-role=regional

helm install kof-storage kof/kof-storage -n kof --create-namespace \
  --set global.clusterName=regional \
  --set victoriametrics.enabled=true \
  --set jaeger.enabled=true \
  --set grafana.enabled=false
```

### Step 3: Child Clusters

```bash
# Install on each workload cluster
kubectl label cluster child-cluster k0rdent.mirantis.com/kof-cluster-role=child

helm install kof-collectors kof/kof-collectors -n kof --create-namespace \
  --set global.clusterName=child-1 \
  --set kof.metrics.endpoint=https://vmauth.regional.yourdomain.com/vm/insert/0/prometheus/api/v1/write \
  --set kof.logs.endpoint=https://vmauth.regional.yourdomain.com/vli/insert/opentelemetry/v1/logs \
  --set kof.traces.endpoint=https://jaeger.regional.yourdomain.com/collector
```

## 🔧 Common Configuration Tasks

### Enable Istio Service Mesh

```bash
# Label namespace for Istio injection
kubectl label namespace kof istio-injection=enabled

# Deploy Istio configuration
helm install kof-istio kof/kof-istio -n istio-system --create-namespace
```

### Configure External DNS (AWS)

```bash
# Create AWS credentials secret
kubectl create secret generic external-dns-aws-credentials -n kof \
  --from-literal=access-key-id=YOUR_ACCESS_KEY \
  --from-literal=secret-access-key=YOUR_SECRET_KEY

# Enable in values
cat >> values.yaml <<EOF
external-dns:
  enabled: true
  provider:
    name: aws
  env:
    - name: AWS_DEFAULT_REGION
      value: us-east-1
EOF
```

### Setup Dex SSO with Google

```bash
# Create Dex configuration
cat > dex-values.yaml <<EOF
dex:
  enabled: true
  config:
    connectors:
      - type: google
        id: google
        name: Google
        config:
          clientID: your-google-client-id
          clientSecret: your-google-client-secret
          redirectURI: https://dex.yourdomain.com/callback
EOF

helm upgrade kof-mothership kof/kof-mothership -n kof -f dex-values.yaml
```

## 🔍 Verification Steps

### Check Component Status

```bash
# Verify all pods are running
kubectl get pods -n kof

# Check operator logs
kubectl logs -l app.kubernetes.io/name=kof-operator -n kof

# Verify metrics collection
kubectl port-forward svc/kof-mothership-kof-operator-ui 9090:9090 -n kof
# Visit http://localhost:9090/api/targets
```

### Test Data Flow

```bash
# Create test application with metrics
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-app
  template:
    metadata:
      labels:
        app: test-app
      annotations:
        instrumentation.opentelemetry.io/inject-python: "true"
    spec:
      containers:
      - name: app
        image: python:3.9-slim
        command: ["python", "-c", "import time; import random; [time.sleep(random.uniform(0.1, 2.0)) for _ in iter(int, 1)]"]
EOF
```

### Access Dashboards

1. **Grafana**: http://localhost:3000 (or your ingress)
2. **KOF Operator UI**: http://localhost:9090
3. **Jaeger**: Port-forward jaeger service on port 16686

## 🚨 Troubleshooting

### Common Issues

**Pods stuck in Pending**:
```bash
# Check resource constraints
kubectl describe nodes
kubectl top nodes
```

**Operator not working**:
```bash
# Check RBAC and CRDs
kubectl get crd | grep kof
kubectl auth can-i create clusterdeployments --as=system:serviceaccount:kof:kof-mothership-kof-operator
```

**Metrics not flowing**:
```bash
# Check collector configuration
kubectl get opentelemetrycollector -n kof -o yaml
kubectl logs -l app.kubernetes.io/name=opentelemetry-collector -n kof
```

**Storage issues**:
```bash
# Check PVC status
kubectl get pvc -n kof
kubectl describe pvc -n kof
```

### Getting Help

1. **Check logs**: Use `kubectl logs` on failing pods
2. **Generate support bundle**: `make support-bundle` (if using local setup)
3. **Community**: [GitHub Discussions](https://github.com/k0rdent/kof/discussions)
4. **Issues**: [GitHub Issues](https://github.com/k0rdent/kof/issues)

## 🎯 Next Steps

Once KOF is running:

1. **Explore Dashboards**: Check pre-built Grafana dashboards
2. **Configure Alerts**: Setup alert rules for your environment
3. **Add Applications**: Instrument your applications for tracing
4. **Scale Up**: Add more regional and child clusters
5. **Security**: Configure Dex SSO and Istio for production

## 📚 Additional Resources

- [Production Deployment Guide](PRODUCTION.md)
- [Security Configuration](SECURITY.md)
- [Architecture Deep Dive](README.md)
- [Development Setup](dev.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)

---

🎉 **Congratulations!** You now have a running KOF deployment. Happy monitoring! 
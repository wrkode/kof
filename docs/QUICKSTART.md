# KOF Quick Start Guide

Get KOF up and running in 15 minutes on any Kubernetes cluster! This guide covers deployment on real Kubernetes clusters including k0s, k3s, AKS, GKE, and EKS.

## 📋 Prerequisites

Before starting, ensure you have:

- **Kubernetes cluster** (1.19+) with admin access
- **Helm** 3.0+ installed
- **kubectl** configured for your cluster
- **Internet connectivity** for pulling images
- **Git** for cloning repositories

### System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **CPU** | 2 cores | 4+ cores |
| **Memory** | 4 GB | 8+ GB |
| **Storage** | 25 GB | 50+ GB |
| **Nodes** | 1 | 3+ |

## 🚀 15-Minute Setup (Any Kubernetes Cluster)

This streamlined setup works on any Kubernetes cluster including:
- **k0s** (Zero friction Kubernetes)
- **k3s** (Lightweight Kubernetes)
- **AKS** (Azure Kubernetes Service)
- **GKE** (Google Kubernetes Engine)
- **EKS** (Amazon Elastic Kubernetes Service)
- **RKE2** (Rancher Kubernetes Engine)
- **kubeadm** (Standard Kubernetes)

### Step 1: Verify Cluster Access

```bash
# Verify cluster connectivity
kubectl cluster-info
kubectl get nodes

# Check available storage classes
kubectl get storageclass

# Verify you have cluster-admin permissions
kubectl auth can-i create clusterrole --all-namespaces
```

### Step 2: Install Dependencies

```bash
# Install cert-manager for TLS
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.4/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=Available --timeout=300s deployment/cert-manager -n cert-manager

# Install ingress controller (choose based on your cluster)
# For cloud providers (AKS/GKE/EKS):
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml

# For on-premises (k0s/k3s/kubeadm):
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/baremetal/deploy.yaml

# Wait for ingress controller
kubectl wait --for=condition=Available --timeout=300s deployment/ingress-nginx-controller -n ingress-nginx
```

### Step 3: Add KOF Helm Repository

```bash
# Add the KOF Helm repository
helm repo add kof oci://ghcr.io/k0rdent/kof/charts
helm repo update

# Verify repository is added
helm search repo kof
```

### Step 4: Configure Values

```bash
# Get your default storage class
DEFAULT_STORAGE_CLASS=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}')

# If no default storage class, use the first available
if [ -z "$DEFAULT_STORAGE_CLASS" ]; then
    DEFAULT_STORAGE_CLASS=$(kubectl get storageclass -o jsonpath='{.items[0].metadata.name}')
fi

echo "Using storage class: $DEFAULT_STORAGE_CLASS"

# Create quick-start values file
cat > quickstart-values.yaml <<EOF
global:
  clusterName: quickstart
  storageClass: "$DEFAULT_STORAGE_CLASS"

# Enable single-cluster mode (all components)
grafana:
  enabled: true
  security:
    create_secret: true
  persistence:
    enabled: true
    size: 10Gi

victoriametrics:
  enabled: true
  vmcluster:
    enabled: true
    replicationFactor: 1
    replicaCount: 1

jaeger:
  enabled: true
  storage:
    type: memory

# Disable external dependencies not needed for quickstart
dex:
  enabled: false

external-dns:
  enabled: false

istio:
  enabled: false

# Use NodePort for easy access on any cluster
service:
  type: NodePort
EOF
```

### Step 5: Deploy KOF

```bash
# Deploy KOF components in the correct order
helm install kof-operators kof/kof-operators -n kof --create-namespace --wait

helm install kof-storage kof/kof-storage -n kof -f quickstart-values.yaml --wait

helm install kof-collectors kof/kof-collectors -n kof -f quickstart-values.yaml --wait

helm install kof-mothership kof/kof-mothership -n kof -f quickstart-values.yaml --wait
```

### Step 6: Verify Installation

```bash
# Check all pods are running
kubectl get pods -n kof

# Check services
kubectl get svc -n kof

# Verify ingress (if using ingress controller)
kubectl get ingress -n kof
```

### Step 7: Access KOF

#### Option A: Port Forward (Works on any cluster)

```bash
# Access Grafana UI
kubectl port-forward svc/grafana 3000:3000 -n kof &

# Access KOF Operator UI
kubectl port-forward svc/kof-mothership-kof-operator-ui 9090:9090 -n kof &

# Access VictoriaMetrics
kubectl port-forward svc/vmselect-vmcluster 8481:8481 -n kof &

# Access Jaeger UI
kubectl port-forward svc/jaeger-query 16686:16686 -n kof &
```

#### Option B: NodePort (On-premises clusters)

```bash
# Get NodePort IPs and ports
kubectl get svc -n kof | grep NodePort

# Access via any node IP and the assigned port
echo "Access Grafana at: http://$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}'):$(kubectl get svc grafana -n kof -o jsonpath='{.spec.ports[0].nodePort}')"
```

#### Option C: LoadBalancer (Cloud providers)

```bash
# Get LoadBalancer IPs (for cloud providers)
kubectl get svc -n kof | grep LoadBalancer

# Access via the external IP
echo "Access Grafana at: http://$(kubectl get svc grafana -n kof -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
```

### Step 8: Get Login Credentials

```bash
# Get Grafana admin credentials
GRAFANA_USER=$(kubectl get secret grafana-admin-credentials -n kof -o jsonpath='{.data.GF_SECURITY_ADMIN_USER}' | base64 -d)
GRAFANA_PASSWORD=$(kubectl get secret grafana-admin-credentials -n kof -o jsonpath='{.data.GF_SECURITY_ADMIN_PASSWORD}' | base64 -d)

echo "Grafana Login:"
echo "Username: $GRAFANA_USER"
echo "Password: $GRAFANA_PASSWORD"
```

## 🌐 Cloud Provider Specific Instructions

### Amazon EKS

```bash
# Install AWS Load Balancer Controller
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"

# Update values for EKS
cat >> quickstart-values.yaml <<EOF
ingress:
  enabled: true
  className: alb
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
EOF
```

### Google GKE

```bash
# Update values for GKE
cat >> quickstart-values.yaml <<EOF
ingress:
  enabled: true
  className: gce
  annotations:
    kubernetes.io/ingress.class: gce
    kubernetes.io/ingress.global-static-ip-name: kof-ip
EOF
```

### Azure AKS

```bash
# Update values for AKS
cat >> quickstart-values.yaml <<EOF
ingress:
  enabled: true
  className: azure/application-gateway
  annotations:
    kubernetes.io/ingress.class: azure/application-gateway
EOF
```

### k0s Clusters

```bash
# k0s specific storage class
DEFAULT_STORAGE_CLASS="local-path"

# Update values for k0s
cat >> quickstart-values.yaml <<EOF
global:
  storageClass: "local-path"
EOF
```

### k3s Clusters

```bash
# k3s comes with Traefik ingress controller
# Update values for k3s
cat >> quickstart-values.yaml <<EOF
ingress:
  enabled: true
  className: traefik
  annotations:
    kubernetes.io/ingress.class: traefik
EOF
```

## 🏢 Advanced Multi-Cluster Setup

For production environments, deploy KOF across multiple clusters:

### Architecture Overview

```
[Management Cluster] ──► [Regional Cluster] ──► [Child Cluster 1]
        │                        │                      │
        │                        │                [Child Cluster 2]
        │                        │                      │
        └─── UI & Control        └─── Storage      └─── Workloads
```

### Step 1: Management Cluster

```bash
# Deploy only management components
helm install kof-mothership kof/kof-mothership -n kof --create-namespace \
  --set global.clusterRole=management \
  --set grafana.enabled=true \
  --set victoriametrics.enabled=false \
  --set jaeger.enabled=false
```

### Step 2: Regional Cluster

```bash
# Deploy storage components
helm install kof-storage kof/kof-storage -n kof --create-namespace \
  --set global.clusterRole=regional \
  --set grafana.enabled=false \
  --set victoriametrics.enabled=true \
  --set jaeger.enabled=true
```

### Step 3: Child Clusters

```bash
# Deploy only collectors
helm install kof-collectors kof/kof-collectors -n kof --create-namespace \
  --set global.clusterRole=child \
  --set global.regionalEndpoint=https://regional.yourdomain.com
```

## 🔧 Common Configuration Tasks

### Enable Persistent Storage

```bash
# For cloud providers with dynamic provisioning
cat >> quickstart-values.yaml <<EOF
persistence:
  enabled: true
  size: 50Gi
  storageClass: "fast-ssd"  # Use your preferred storage class
EOF
```

### Configure Resource Limits

```bash
# Adjust resources based on your cluster size
cat >> quickstart-values.yaml <<EOF
resources:
  limits:
    cpu: 2000m
    memory: 4Gi
  requests:
    cpu: 500m
    memory: 1Gi
EOF
```

### Enable SSL/TLS

```bash
# For clusters with cert-manager
cat >> quickstart-values.yaml <<EOF
ingress:
  enabled: true
  tls:
    enabled: true
    secretName: kof-tls-secret
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
EOF
```

## 🔍 Verification & Testing

### Check Installation Health

```bash
# Verify all components are running
kubectl get pods -n kof -o wide

# Check resource usage
kubectl top pods -n kof

# Verify metrics collection
kubectl port-forward svc/kof-mothership-kof-operator-ui 9090:9090 -n kof &
# Visit http://localhost:9090/targets to see metrics targets
```

### Test Data Collection

```bash
# Deploy a test application
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-metrics-app
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-metrics-app
  template:
    metadata:
      labels:
        app: test-metrics-app
    spec:
      containers:
      - name: metrics-generator
        image: nginx:latest
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: test-metrics-app
  namespace: default
spec:
  selector:
    app: test-metrics-app
  ports:
  - port: 80
    targetPort: 80
EOF

# Verify metrics are being collected
# Check in Grafana dashboards after 1-2 minutes
```

## 🚨 Troubleshooting

### Common Issues

**Pods stuck in Pending state**:
```bash
# Check node resources
kubectl describe nodes
kubectl top nodes

# Check storage class
kubectl get storageclass
kubectl describe storageclass $DEFAULT_STORAGE_CLASS
```

**Ingress not working**:
```bash
# Check ingress controller
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

**Metrics not appearing**:
```bash
# Check collectors
kubectl logs -n kof -l app.kubernetes.io/name=opentelemetry-collector
kubectl get opentelemetrycollector -n kof
```

**Storage issues**:
```bash
# Check persistent volumes
kubectl get pv,pvc -n kof
kubectl describe pvc -n kof
```

### Getting Help

1. **Check pod logs**: `kubectl logs -n kof <pod-name>`
2. **Check events**: `kubectl get events -n kof --sort-by=.metadata.creationTimestamp`
3. **Community Support**: [GitHub Discussions](https://github.com/k0rdent/kof/discussions)
4. **Report Issues**: [GitHub Issues](https://github.com/k0rdent/kof/issues)

## 🎯 Next Steps

Once KOF is running:

1. **Explore Dashboards**: Browse pre-built Grafana dashboards
2. **Configure Alerts**: Set up alerting rules for your environment
3. **Add Applications**: Instrument your apps with OpenTelemetry
4. **Scale Deployment**: Add more regional and child clusters
5. **Enhance Security**: Configure authentication and network policies

## 📚 Additional Resources

- [Production Deployment Guide](PRODUCTION.md)
- [Security Configuration](SECURITY.md)
- [Architecture Overview](README.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)

---

🎉 **Congratulations!** You now have KOF running on your Kubernetes cluster! Happy observing! 
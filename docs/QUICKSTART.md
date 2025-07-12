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

## 🎯 Deployment Scenarios

Choose the deployment scenario that best fits your needs:

### 📊 Scenario Comparison

| Scenario | Use Case | Complexity | Features |
|----------|----------|------------|----------|
| **Single Cluster** | Development, testing, proof-of-concept | Low | All components in one cluster |
| **Multi-Cluster** | Production, scalability, separation of concerns | Medium | Dedicated management, storage, and workload clusters |
| **k0rdent-Managed** | Enterprise, fleet management | High | Full k0rdent integration with automated cluster lifecycle |

## 🚀 15-Minute Setup (Single Cluster)

This streamlined setup works on any Kubernetes cluster including k0s, k3s, AKS, GKE, and EKS.

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

### Step 3: Prepare for KOF Installation

```bash
# Option A: Install from OCI Registry (Recommended)
# No setup required - we install directly from the OCI registry
# The charts are available at: oci://ghcr.io/k0rdent/kof/charts/<chart-name>

# Option B: Use Local Charts (For Development)
# Clone the repository and use local charts
git clone https://github.com/k0rdent/kof.git
cd kof
# Then use ./charts/<chart-name> instead of OCI URLs in the commands below
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
helm install kof-operators oci://ghcr.io/k0rdent/kof/charts/kof-operators -n kof --create-namespace --wait

helm install kof-storage oci://ghcr.io/k0rdent/kof/charts/kof-storage -n kof -f quickstart-values.yaml --wait

helm install kof-collectors oci://ghcr.io/k0rdent/kof/charts/kof-collectors -n kof -f quickstart-values.yaml --wait

helm install kof-mothership oci://ghcr.io/k0rdent/kof/charts/kof-mothership -n kof -f quickstart-values.yaml --wait
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

## 🏢 Production Multi-Cluster Setup

For production environments, deploy KOF across multiple clusters with enhanced features:

### Architecture Overview

```
[Management Cluster] ──► [Regional Cluster] ──► [Child Cluster 1]
        │                        │                      │
        │                        │                [Child Cluster 2]
        │                        │                      │
        └─── UI & Control        └─── Storage      └─── Workloads
        └─── DNS & Istio         └─── Aggregation  └─── Collection
```

### Step 1: Management Cluster

```bash
# Deploy only management components
helm install kof-mothership oci://ghcr.io/k0rdent/kof/charts/kof-mothership -n kof --create-namespace \
  --set global.clusterRole=management \
  --set grafana.enabled=true \
  --set victoriametrics.enabled=false \
  --set jaeger.enabled=false
```

### Step 2: Regional Cluster

```bash
# Deploy storage components
helm install kof-storage oci://ghcr.io/k0rdent/kof/charts/kof-storage -n kof --create-namespace \
  --set global.clusterRole=regional \
  --set grafana.enabled=false \
  --set victoriametrics.enabled=true \
  --set jaeger.enabled=true
```

### Step 3: Child Clusters

```bash
# Deploy only collectors
helm install kof-collectors oci://ghcr.io/k0rdent/kof/charts/kof-collectors -n kof --create-namespace \
  --set global.clusterRole=child \
  --set global.regionalEndpoint=https://regional.yourdomain.com
```

## 🌍 DNS Auto-Configuration

For production setups, automate DNS record management:

### AWS Route53 Setup

```bash
# Create external-dns IAM user with Route53 permissions
# Policy: https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/aws.md#iam-policy

# Create credentials file
cat > external-dns-aws-credentials <<EOF
[default]
aws_access_key_id = YOUR_ACCESS_KEY_ID
aws_secret_access_key = YOUR_SECRET_ACCESS_KEY
EOF

# Create secret
kubectl create namespace kof
kubectl create secret generic external-dns-aws-credentials -n kof \
  --from-file external-dns-aws-credentials

# Enable in values
cat >> quickstart-values.yaml <<EOF
external-dns:
  enabled: true
  provider: aws
  domainFilters:
    - yourdomain.com
  policy: sync
EOF
```

### Azure DNS Setup

```bash
# Create service principal with DNS Zone Contributor role
# Follow: https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/azure.md

# Create azure.json
cat > azure.json <<EOF
{
  "tenantId": "YOUR_TENANT_ID",
  "subscriptionId": "YOUR_SUBSCRIPTION_ID",
  "resourceGroup": "YOUR_RESOURCE_GROUP",
  "aadClientId": "YOUR_SP_APP_ID",
  "aadClientSecret": "YOUR_SP_PASSWORD"
}
EOF

# Create secret
kubectl create secret generic external-dns-azure-credentials -n kof \
  --from-file azure.json

# Enable in values
cat >> quickstart-values.yaml <<EOF
external-dns:
  enabled: true
  provider: azure
  domainFilters:
    - yourdomain.com
EOF
```

## 🔒 Istio Service Mesh Integration

For secure multi-cluster communication without external DNS:

### Enable Istio

```bash
# Create and label KOF namespace for Istio injection
kubectl create namespace kof
kubectl label namespace kof istio-injection=enabled

# Install Istio (if not already installed)
curl -L https://istio.io/downloadIstio | sh -
export PATH=$PWD/istio-*/bin:$PATH
istioctl install --set values.defaultRevision=default

# Deploy KOF with Istio configuration
helm install kof-istio oci://ghcr.io/k0rdent/kof/charts/kof-istio -n istio-system --create-namespace
```

### Configure Multi-Cluster Istio

```bash
# For each cluster, configure network and cluster names
cat >> quickstart-values.yaml <<EOF
istio:
  enabled: true
  multiCluster:
    clusterName: cluster-1
    network: network-1
  gateway:
    enabled: true
EOF
```

## 🔧 Advanced Configuration Tasks

### Custom Storage Configuration

```bash
# For cloud providers with high-performance storage
cat >> quickstart-values.yaml <<EOF
global:
  storageClass: "fast-ssd"  # Use your preferred storage class

persistence:
  enabled: true
  size: 100Gi
  storageClass: "premium-ssd"

victoriametrics:
  storage:
    size: 200Gi
    storageClass: "fast-ssd"

jaeger:
  storage:
    elasticsearch:
      enabled: true
      storage:
        size: 100Gi
        storageClass: "ssd"
EOF
```

### Resource Limits and Requests

```bash
# Adjust resources based on your cluster size
cat >> quickstart-values.yaml <<EOF
resources:
  requests:
    cpu: 500m
    memory: 1Gi
  limits:
    cpu: 2000m
    memory: 4Gi

victoriametrics:
  vmcluster:
    vminsert:
      resources:
        requests:
          cpu: 250m
          memory: 512Mi
        limits:
          cpu: 1000m
          memory: 2Gi
    vmselect:
      resources:
        requests:
          cpu: 250m
          memory: 512Mi
        limits:
          cpu: 1000m
          memory: 2Gi
    vmstorage:
      resources:
        requests:
          cpu: 500m
          memory: 1Gi
        limits:
          cpu: 2000m
          memory: 4Gi
EOF
```

### SSL/TLS Configuration

```bash
# For clusters with cert-manager and Let's Encrypt
cat >> quickstart-values.yaml <<EOF
ingress:
  enabled: true
  tls:
    enabled: true
    secretName: kof-tls-secret
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    kubernetes.io/ingress.class: nginx

cert-manager:
  enabled: true
  clusterIssuer:
    enabled: true
    email: admin@yourdomain.com
    acmeServer: https://acme-v02.api.letsencrypt.org/directory
EOF
```

### Custom Endpoints Configuration

```bash
# Override default endpoints for existing infrastructure
cat >> quickstart-values.yaml <<EOF
kof:
  endpoints:
    metrics:
      write: "https://custom-metrics.yourdomain.com/write"
      read: "https://custom-metrics.yourdomain.com/read"
    logs:
      write: "https://custom-logs.yourdomain.com/write"
      read: "https://custom-logs.yourdomain.com/read"
    traces:
      write: "https://custom-traces.yourdomain.com/write"
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
# Deploy a test application with OpenTelemetry instrumentation
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-metrics-app
  namespace: default
  annotations:
    instrumentation.opentelemetry.io/inject-nodejs: "true"
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
        env:
        - name: OTEL_SERVICE_NAME
          value: "test-app"
        - name: OTEL_RESOURCE_ATTRIBUTES
          value: "service.name=test-app,service.version=1.0.0"
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

### Performance Testing

```bash
# Generate load to test metrics collection
kubectl run load-generator --image=busybox:1.28 --restart=Never -- \
  /bin/sh -c "while true; do wget -q -O- http://test-metrics-app.default.svc.cluster.local; sleep 0.1; done"

# Monitor resource usage
kubectl top pods -n kof
kubectl top nodes
```

## 🚨 Troubleshooting

### Common Issues

**Pods stuck in Pending state**:
```bash
# Check node resources
kubectl describe nodes
kubectl top nodes

# Check storage class and PVC status
kubectl get storageclass
kubectl get pvc -n kof
kubectl describe pvc -n kof
```

**Ingress not working**:
```bash
# Check ingress controller
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# Verify ingress configuration
kubectl get ingress -n kof -o yaml
```

**Metrics not appearing**:
```bash
# Check collectors
kubectl logs -n kof -l app.kubernetes.io/name=opentelemetry-collector
kubectl get opentelemetrycollector -n kof

# Check VictoriaMetrics
kubectl logs -n kof -l app.kubernetes.io/name=vminsert
kubectl logs -n kof -l app.kubernetes.io/name=vmselect
```

**DNS resolution issues**:
```bash
# Check external-dns logs
kubectl logs -n kof -l app.kubernetes.io/name=external-dns

# Verify DNS records
nslookup grafana.yourdomain.com
dig +short grafana.yourdomain.com
```

**Istio connectivity issues**:
```bash
# Check Istio sidecar injection
kubectl get pods -n kof -o jsonpath='{.items[*].spec.containers[*].name}' | grep istio-proxy

# Verify Istio configuration
istioctl analyze -n kof
istioctl proxy-config cluster -n kof <pod-name>
```

**Storage issues**:
```bash
# Check persistent volumes
kubectl get pv,pvc -n kof
kubectl describe pvc -n kof

# Check storage class provisioner
kubectl describe storageclass $DEFAULT_STORAGE_CLASS
```

### Getting Help

1. **Check pod logs**: `kubectl logs -n kof <pod-name>`
2. **Check events**: `kubectl get events -n kof --sort-by=.metadata.creationTimestamp`
3. **Generate support bundle**: See [Troubleshooting Guide](TROUBLESHOOTING.md)
4. **Community Support**: [GitHub Discussions](https://github.com/k0rdent/kof/discussions)
5. **Report Issues**: [GitHub Issues](https://github.com/k0rdent/kof/issues)

## 🎯 Next Steps

Once KOF is running:

1. **Explore Dashboards**: Browse pre-built Grafana dashboards for infrastructure and application metrics
2. **Configure Alerts**: Set up alerting rules for your environment using Prometheus AlertManager
3. **Add Applications**: Instrument your apps with OpenTelemetry for distributed tracing
4. **Scale Deployment**: Add more regional and child clusters for larger environments
5. **Enhance Security**: Configure authentication, authorization, and network policies
6. **Integrate with k0rdent**: Migrate to k0rdent-managed clusters for enterprise features

## 🔗 Integration with k0rdent

If you have a [k0rdent management cluster](https://docs.k0rdent.io/next/admin/kof/kof-install/), you can integrate KOF for automated multi-cluster management:

### Prerequisites for k0rdent Integration

```bash
# Verify k0rdent is installed
kubectl get clusterdeployments -n kcm-system

# Check available cluster templates
kubectl get clustertemplates -n kcm-system
```

### Migrate to k0rdent-Managed KOF

```bash
# Label existing clusters for k0rdent management
kubectl label cluster <cluster-name> k0rdent.mirantis.com/kof-cluster-role=regional
kubectl label cluster <cluster-name> k0rdent.mirantis.com/kof-storage-secrets=true

# Deploy using k0rdent ClusterDeployment (see official docs)
```

## 📚 Additional Resources

- [Official KOF Installation Guide](https://docs.k0rdent.io/next/admin/kof/kof-install/) - Enterprise multi-cluster setup with k0rdent
- [Production Deployment Guide](PRODUCTION.md) - Advanced production configurations
- [Security Configuration](SECURITY.md) - Security hardening and best practices
- [Architecture Overview](README.md) - Detailed system architecture
- [Troubleshooting Guide](TROUBLESHOOTING.md) - Common issues and solutions
- [k0rdent Documentation](https://docs.k0rdent.io/) - Full k0rdent platform documentation

---

🎉 **Congratulations!** You now have KOF running on your Kubernetes cluster! Happy observing! 
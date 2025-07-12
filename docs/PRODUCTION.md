# KOF Production Deployment Guide

This guide provides comprehensive instructions for deploying KOF in production environments with high availability, security, and scalability considerations.

## 📋 Pre-Production Checklist

### Infrastructure Requirements

- [ ] **Kubernetes clusters** (1.19+) with high availability
- [ ] **Storage class** configured with backup capabilities
- [ ] **Load balancer** for ingress traffic
- [ ] **DNS management** for custom domains
- [ ] **Certificate management** (Let's Encrypt or internal CA)
- [ ] **Network policies** support
- [ ] **Resource quotas** and limits configured

### Security Requirements

- [ ] **RBAC** policies reviewed and configured
- [ ] **Pod Security Standards** enforced
- [ ] **Network segmentation** implemented
- [ ] **Secrets management** solution in place
- [ ] **Container scanning** integrated
- [ ] **Backup and recovery** procedures tested

### Monitoring Requirements

- [ ] **Resource monitoring** for clusters
- [ ] **Log aggregation** solution
- [ ] **Alerting** configured for critical components
- [ ] **SLA/SLO** definitions established
- [ ] **Incident response** procedures documented

## 🏗️ Architecture Overview

### Production Topology

```
┌─────────────────────────────────────────────────────────────────┐
│                        MOTHERSHIP CLUSTER                      │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │   Grafana UI    │  │  KOF Operator   │  │   Promxy        │ │
│  │   (HA Mode)     │  │  (Leader Elect) │  │  (Multi Replica)│ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                       REGIONAL CLUSTER                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │ VictoriaMetrics │  │ Victoria Logs   │  │     Jaeger      │ │
│  │   (Cluster)     │  │   (Cluster)     │  │   (Production)  │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                        CHILD CLUSTERS                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │  Collectors     │  │  Node Exporter  │  │   OpenCost      │ │
│  │ (DaemonSet)     │  │ (DaemonSet)     │  │                 │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Component Sizing

| Component | Minimum | Recommended | High Availability |
|-----------|---------|-------------|-------------------|
| **Mothership** | 2 CPU, 4GB RAM | 4 CPU, 8GB RAM | 3 nodes, 6 CPU, 16GB RAM |
| **Regional** | 4 CPU, 8GB RAM | 8 CPU, 16GB RAM | 3 nodes, 12 CPU, 32GB RAM |
| **Child** | 1 CPU, 2GB RAM | 2 CPU, 4GB RAM | Based on workload |

## 🔧 Production Configuration

### 1. Mothership Cluster Deployment

#### Create Production Values

```yaml
# production-mothership-values.yaml
global:
  clusterName: mothership-prod
  storageClass: fast-ssd
  imageRegistry: your-registry.com
  random_username_length: 16
  random_password_length: 32

kcm:
  installTemplates: true
  kof:
    operator:
      replicaCount: 2
      resources:
        requests:
          cpu: 200m
          memory: 256Mi
        limits:
          cpu: 500m
          memory: 512Mi
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app.kubernetes.io/name: kof-operator
            topologyKey: kubernetes.io/hostname

grafana:
  enabled: true
  ingress:
    enabled: true
    host: grafana.yourdomain.com
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
      nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
  security:
    create_secret: true
  alerts:
    enabled: true
  pvc:
    resources:
      requests:
        storage: 10Gi

promxy:
  enabled: true
  replicaCount: 3
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: promxy
          topologyKey: kubernetes.io/hostname

cert-manager:
  enabled: true
  cluster-issuer:
    create: true
    provider: letsencrypt
  email: admin@yourdomain.com

dex:
  enabled: true
  config:
    issuer: https://dex.yourdomain.com
    storage:
      type: kubernetes
      config:
        inCluster: true
    staticClients:
      - id: grafana
        name: Grafana
        secret: your-secure-random-secret
        redirectURIs:
          - https://grafana.yourdomain.com/login/generic_oauth
    connectors:
      - type: google
        id: google
        name: Google
        config:
          clientID: your-google-client-id
          clientSecret: your-google-client-secret
          redirectURI: https://dex.yourdomain.com/callback
          hostedDomains:
            - yourdomain.com

victoria-metrics-operator:
  enabled: true
  operator:
    disable_prometheus_converter: false
  crds:
    cleanup:
      enabled: true

# Production alerting rules
defaultRules:
  create: true
  rules:
    etcd: true
    general: true
    k8sContainerResource: true
    kubernetesApps: true
    kubernetesResources: true
    kubernetesSystem: true
    node: true
    prometheus: true

# Custom alert rules for KOF
customAlertRules:
  kof.rules:
    groups:
    - name: kof.rules
      rules:
      - alert: KOFOperatorDown
        expr: up{job="kof-operator"} == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: KOF Operator is down
          description: "KOF Operator has been down for more than 5 minutes"
      
      - alert: HighMemoryUsage
        expr: (container_memory_working_set_bytes / container_spec_memory_limit_bytes * 100) > 80
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: High memory usage detected
          description: "Container {{ $labels.container }} in pod {{ $labels.pod }} is using {{ $value }}% of memory"
```

#### Deploy Mothership

```bash
# Create namespace with security labels
kubectl create namespace kof
kubectl label namespace kof \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted

# Deploy with production values
helm install kof-mothership oci://ghcr.io/k0rdent/kof/charts/kof-mothership \
  -n kof \
  -f production-mothership-values.yaml \
  --wait --timeout=10m
```

### 2. Regional Cluster Deployment

#### Create Regional Values

```yaml
# production-regional-values.yaml
global:
  clusterName: regional-prod
  storageClass: fast-ssd

victoriametrics:
  enabled: true
  vmcluster:
    enabled: true
    replicationFactor: 2
    retentionPeriod: "90d"
    
    vminsert:
      replicaCount: 3
      resources:
        requests:
          cpu: 200m
          memory: 512Mi
        limits:
          cpu: 500m
          memory: 1Gi
      storage:
        size: 20Gi
    
    vmselect:
      replicaCount: 3
      resources:
        requests:
          cpu: 200m
          memory: 512Mi
        limits:
          cpu: 500m
          memory: 1Gi
      storage:
        size: 10Gi
    
    vmstorage:
      replicaCount: 3
      resources:
        requests:
          cpu: 500m
          memory: 1Gi
        limits:
          cpu: 1000m
          memory: 2Gi
      storage:
        size: 100Gi

  vmauth:
    enabled: true
    credentials:
      credentials_secret_name: storage-vmuser-credentials
      username_key: username
      password_key: password
    ingress:
      host: vmauth.yourdomain.com
      annotations:
        cert-manager.io/cluster-issuer: letsencrypt-prod
        nginx.ingress.kubernetes.io/force-ssl-redirect: "true"

  vmalert:
    enabled: true
    replicaCount: 2
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi

victoria-logs-cluster:
  enabled: true
  
  vlinsert:
    replicaCount: 3
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 500m
        memory: 1Gi
  
  vlselect:
    replicaCount: 3
    resources:
      requests:
        cpu: 200m
        memory: 512Mi
      limits:
        cpu: 500m
        memory: 1Gi
  
  vlstorage:
    replicaCount: 3
    persistentVolume:
      enabled: true
      size: 50Gi
    resources:
      requests:
        cpu: 300m
        memory: 1Gi
      limits:
        cpu: 600m
        memory: 2Gi

jaeger:
  enabled: true
  strategy: production
  collector:
    replicaCount: 3
    resources:
      requests:
        cpu: 200m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
  
  storage:
    type: elasticsearch
    elasticsearch:
      server-urls: https://elasticsearch.yourdomain.com:9200
      username: jaeger
      password: your-elasticsearch-password
  
  ingress:
    enabled: true
    host: jaeger.yourdomain.com
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod

grafana:
  enabled: false  # Disabled in regional, enabled in mothership

# Istio configuration for secure communication
istio_endpoints: true
```

#### Deploy Regional

```bash
# Label cluster for KOF
kubectl label cluster regional-cluster \
  k0rdent.mirantis.com/kof-cluster-role=regional \
  k0rdent.mirantis.com/kof-storage-secrets=true

# Deploy regional storage
helm install kof-storage oci://ghcr.io/k0rdent/kof/charts/kof-storage \
  -n kof --create-namespace \
  -f production-regional-values.yaml \
  --wait --timeout=15m
```

### 3. Child Cluster Deployment

#### Create Child Values

```yaml
# production-child-values.yaml
global:
  clusterName: child-prod-1

kof:
  basic_auth: true
  metrics:
    endpoint: https://vmauth.yourdomain.com/vm/insert/0/prometheus/api/v1/write
    credentials_secret_name: storage-vmuser-credentials
  logs:
    endpoint: https://vmauth.yourdomain.com/vli/insert/opentelemetry/v1/logs
    credentials_secret_name: storage-vmuser-credentials
  traces:
    endpoint: https://jaeger.yourdomain.com/collector
  instrumentation:
    enabled: true

collectors:
  enabled: true
  node:
    run_as_root: false
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 200m
        memory: 512Mi
  
  k8scluster:
    resources:
      requests:
        cpu: 50m
        memory: 128Mi
      limits:
        cpu: 100m
        memory: 256Mi

opencost:
  enabled: true
  opencost:
    exporter:
      defaultClusterId: child-prod-1
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 200m
          memory: 256Mi
    prometheus:
      external:
        enabled: true
        url: https://vmauth.yourdomain.com/vm/select/0/prometheus

# Resource monitoring
kubernetesServiceMonitors:
  enabled: true
  ignoreNamespaceSelectors: false
```

#### Deploy Child

```bash
# Label cluster for KOF
kubectl label cluster child-cluster \
  k0rdent.mirantis.com/kof-cluster-role=child

# Create credentials secret (from regional cluster)
kubectl create secret generic storage-vmuser-credentials -n kof \
  --from-literal=username=your-vm-username \
  --from-literal=password=your-vm-password

# Deploy collectors
helm install kof-collectors oci://ghcr.io/k0rdent/kof/charts/kof-collectors \
  -n kof --create-namespace \
  -f production-child-values.yaml \
  --wait --timeout=10m
```

## 🔒 Security Hardening

### 1. Network Security

#### Network Policies

```yaml
# kof-network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: kof-network-policy
  namespace: kof
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: kof
    - namespaceSelector:
        matchLabels:
          name: istio-system
  - from: []
    ports:
    - protocol: TCP
      port: 8080  # Grafana
    - protocol: TCP
      port: 9090  # Promxy
    - protocol: TCP
      port: 8427  # VMAuth
  egress:
  - {}  # Allow all egress for now, restrict as needed
```

#### Istio Service Mesh (Recommended)

```bash
# Enable Istio for secure communication
kubectl label namespace kof istio-injection=enabled

# Deploy Istio configuration
helm install kof-istio oci://ghcr.io/k0rdent/kof/charts/kof-istio \
  -n istio-system --create-namespace \
  --set global.meshID=kof-prod \
  --set global.network=prod-network
```

### 2. RBAC Configuration

#### Minimal RBAC for KOF Operator

```yaml
# kof-rbac-production.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kof-operator-production
rules:
- apiGroups: [""]
  resources: ["secrets", "configmaps", "services"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["monitoring.coreos.com"]
  resources: ["servicemonitors", "prometheusrules"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
- apiGroups: ["kof.k0rdent.mirantis.com"]
  resources: ["promxyservergroups"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: kof-operator-production
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: kof-operator-production
subjects:
- kind: ServiceAccount
  name: kof-mothership-kof-operator
  namespace: kof
```

### 3. Pod Security Standards

```yaml
# kof-pod-security.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: kof
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### 4. Secrets Management

#### External Secrets Integration

```yaml
# external-secrets-config.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: kof-secret-store
  namespace: kof
spec:
  provider:
    vault:
      server: https://vault.yourdomain.com
      path: kof
      version: v2
      auth:
        kubernetes:
          mountPath: kubernetes
          role: kof-role
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: storage-vmuser-credentials
  namespace: kof
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: kof-secret-store
    kind: SecretStore
  target:
    name: storage-vmuser-credentials
    creationPolicy: Owner
  data:
  - secretKey: username
    remoteRef:
      key: storage
      property: username
  - secretKey: password
    remoteRef:
      key: storage
      property: password
```

## 📊 Monitoring & Alerting

### 1. Infrastructure Monitoring

#### Custom Alerts

```yaml
# kof-production-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: kof-production-alerts
  namespace: kof
spec:
  groups:
  - name: kof.production
    rules:
    - alert: KOFComponentDown
      expr: up{job=~"kof-.*"} == 0
      for: 5m
      labels:
        severity: critical
        team: platform
      annotations:
        summary: "KOF component {{ $labels.job }} is down"
        description: "KOF component {{ $labels.job }} on {{ $labels.instance }} has been down for more than 5 minutes"
        runbook_url: "https://runbooks.yourdomain.com/kof/component-down"

    - alert: HighVMStorageUsage
      expr: (vm_free_disk_space_bytes / vm_available_disk_space_bytes) * 100 < 10
      for: 10m
      labels:
        severity: warning
        team: platform
      annotations:
        summary: "VictoriaMetrics storage usage is high"
        description: "VM storage on {{ $labels.instance }} has less than 10% free space"
        
    - alert: GrafanaHighMemoryUsage
      expr: container_memory_working_set_bytes{pod=~"grafana-.*"} / container_spec_memory_limit_bytes > 0.8
      for: 15m
      labels:
        severity: warning
        team: platform
      annotations:
        summary: "Grafana high memory usage"
        description: "Grafana pod {{ $labels.pod }} is using {{ $value | humanizePercentage }} of memory"

    - alert: JaegerTracesDropped
      expr: increase(jaeger_collector_traces_dropped_total[5m]) > 100
      for: 5m
      labels:
        severity: warning
        team: platform
      annotations:
        summary: "Jaeger is dropping traces"
        description: "Jaeger collector has dropped {{ $value }} traces in the last 5 minutes"
```

### 2. SLI/SLO Definitions

```yaml
# kof-slo-config.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: kof-slo
  namespace: kof
spec:
  groups:
  - name: kof.slo
    interval: 30s
    rules:
    # Grafana Availability SLI
    - record: grafana:availability:rate5m
      expr: avg_over_time(up{job="grafana"}[5m])
    
    # Grafana Response Time SLI
    - record: grafana:response_time:p99:5m
      expr: histogram_quantile(0.99, rate(grafana_http_request_duration_seconds_bucket[5m]))
    
    # Data Ingestion Success Rate
    - record: kof:data_ingestion:success_rate:5m
      expr: |
        (
          rate(vminsert_requests_total{status_code="2xx"}[5m]) /
          rate(vminsert_requests_total[5m])
        )
    
    # Query Performance SLI
    - record: kof:query_performance:p95:5m
      expr: histogram_quantile(0.95, rate(vmselect_request_duration_seconds_bucket[5m]))

    # SLO Alerts
    - alert: GrafanaAvailabilitySLOBreach
      expr: grafana:availability:rate5m < 0.99
      for: 5m
      labels:
        severity: critical
        slo: availability
      annotations:
        summary: "Grafana availability SLO breach"
        description: "Grafana availability is {{ $value | humanizePercentage }}, below 99% SLO"
```

### 3. Log Analysis Rules

```yaml
# log-analysis-rules.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: log-analysis-rules
  namespace: kof
data:
  rules.yaml: |
    groups:
    - name: error_detection
      rules:
      - alert: HighErrorRate
        expr: |
          (
            sum(rate(log_messages_total{level="error"}[5m])) by (namespace, pod) /
            sum(rate(log_messages_total[5m])) by (namespace, pod)
          ) > 0.05
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High error rate detected in {{ $labels.namespace }}/{{ $labels.pod }}"
          description: "Error rate is {{ $value | humanizePercentage }} in the last 5 minutes"
    
    - name: security_events
      rules:
      - alert: UnauthorizedAPIAccess
        expr: increase(log_messages_total{level="warn", message=~".*unauthorized.*"}[5m]) > 10
        for: 2m
        labels:
          severity: critical
          security: true
        annotations:
          summary: "Multiple unauthorized API access attempts detected"
          description: "{{ $value }} unauthorized access attempts in the last 5 minutes"
```

## 🔄 Backup & Recovery

### 1. VictoriaMetrics Backup

```yaml
# vm-backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: vm-backup
  namespace: kof
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: vmbackup
            image: victoriametrics/vmbackup:latest
            env:
            - name: S3_BUCKET
              value: "your-backup-bucket"
            - name: AWS_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: backup-credentials
                  key: access-key-id
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: backup-credentials
                  key: secret-access-key
            command:
            - /vmbackup-prod
            - -snapshot.createURL=http://vmstorage:8482/snapshot/create
            - -dst=s3://your-backup-bucket/vm-backup/$(date +%Y-%m-%d)
            volumeMounts:
            - name: storage
              mountPath: /storage
          volumes:
          - name: storage
            persistentVolumeClaim:
              claimName: vmstorage-db-vmstorage-cluster-0
          restartPolicy: OnFailure
```

### 2. Grafana Dashboard Backup

```yaml
# grafana-backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: grafana-backup
  namespace: kof
spec:
  schedule: "0 3 * * *"  # Daily at 3 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: grafana-backup
            image: your-registry.com/grafana-backup:latest
            env:
            - name: GRAFANA_URL
              value: "http://grafana-vm-service:3000"
            - name: GRAFANA_TOKEN
              valueFrom:
                secretKeyRef:
                  name: grafana-backup-token
                  key: token
            - name: BACKUP_LOCATION
              value: "s3://your-backup-bucket/grafana-backup"
            command:
            - /backup-script.sh
          restartPolicy: OnFailure
```

### 3. Disaster Recovery Procedures

#### Recovery Runbook

```bash
#!/bin/bash
# disaster-recovery.sh

set -euo pipefail

BACKUP_DATE=${1:-latest}
CLUSTER_NAME=${2:-regional-prod}

echo "Starting disaster recovery for cluster: $CLUSTER_NAME"
echo "Using backup from: $BACKUP_DATE"

# 1. Restore VictoriaMetrics data
echo "Restoring VictoriaMetrics data..."
kubectl exec -n kof vmstorage-cluster-0 -- /vmrestore-prod \
  -src=s3://your-backup-bucket/vm-backup/$BACKUP_DATE \
  -storageDataPath=/storage

# 2. Restore Grafana dashboards
echo "Restoring Grafana dashboards..."
kubectl create job --from=cronjob/grafana-restore grafana-restore-$(date +%s) -n kof

# 3. Verify data integrity
echo "Verifying data integrity..."
kubectl exec -n kof vmselect-cluster-0 -- curl -s "http://localhost:8481/api/v1/query?query=up" | jq .

# 4. Check all services are healthy
echo "Checking service health..."
kubectl get pods -n kof
kubectl get svc -n kof

echo "Disaster recovery completed successfully!"
```

## 🚀 Scaling & Performance

### 1. Horizontal Pod Autoscaling

```yaml
# hpa-configurations.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: vminsert-hpa
  namespace: kof
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: vminsert-cluster
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: vmselect-hpa
  namespace: kof
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: vmselect-cluster
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

### 2. Vertical Pod Autoscaling

```yaml
# vpa-configurations.yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: vmstorage-vpa
  namespace: kof
spec:
  targetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: vmstorage-cluster
  updatePolicy:
    updateMode: "Auto"
  resourcePolicy:
    containerPolicies:
    - containerName: vmstorage
      maxAllowed:
        cpu: 2
        memory: 4Gi
      minAllowed:
        cpu: 100m
        memory: 256Mi
```

### 3. Performance Tuning

#### VictoriaMetrics Optimization

```yaml
# vm-performance-config.yaml
victoriametrics:
  vmcluster:
    vmstorage:
      extraArgs:
        - "-memory.allowedPercent=80"
        - "-search.maxConcurrentRequests=16"
        - "-search.maxMemoryPerQuery=2GB"
        - "-retentionPeriod=90d"
        - "-storageDataPath=/storage"
        - "-loggerLevel=WARN"
    
    vminsert:
      extraArgs:
        - "-maxConcurrentInserts=32"
        - "-maxInsertRequestSize=32MB"
        - "-loggerLevel=WARN"
    
    vmselect:
      extraArgs:
        - "-search.maxConcurrentRequests=32"
        - "-search.maxQueryDuration=300s"
        - "-search.maxSamplesPerQuery=1000000000"
        - "-loggerLevel=WARN"
```

## 🔧 Maintenance Procedures

### 1. Upgrade Strategy

#### Rolling Upgrade Process

```bash
#!/bin/bash
# rolling-upgrade.sh

CURRENT_VERSION=$(helm list -n kof -o json | jq -r '.[] | select(.name=="kof-mothership") | .chart' | cut -d'-' -f3)
TARGET_VERSION=${1:-latest}

echo "Upgrading KOF from $CURRENT_VERSION to $TARGET_VERSION"

# 1. Backup current state
echo "Creating backup..."
kubectl create backup kof-backup-$(date +%s) --include-namespaces=kof

# 2. Upgrade operators first
echo "Upgrading operators..."
helm upgrade kof-operators oci://ghcr.io/k0rdent/kof/charts/kof-operators:$TARGET_VERSION \
  -n kof --wait --timeout=10m

# 3. Upgrade mothership
echo "Upgrading mothership..."
helm upgrade kof-mothership oci://ghcr.io/k0rdent/kof/charts/kof-mothership:$TARGET_VERSION \
  -n kof -f production-mothership-values.yaml --wait --timeout=15m

# 4. Upgrade regional clusters
echo "Upgrading regional clusters..."
for cluster in $(kubectl get clusters -l k0rdent.mirantis.com/kof-cluster-role=regional -o name); do
  echo "Upgrading $cluster"
  kubectl patch $cluster --type='merge' -p='{"spec":{"template":"kof-storage:'$TARGET_VERSION'"}}'
done

# 5. Verify upgrade
echo "Verifying upgrade..."
kubectl get pods -n kof
helm list -n kof

echo "Upgrade completed successfully!"
```

### 2. Health Checks

```bash
#!/bin/bash
# health-check.sh

echo "Running KOF health checks..."

# Check all pods are running
echo "Checking pod status..."
if ! kubectl get pods -n kof --no-headers | grep -v Running | grep -v Completed; then
  echo "✅ All pods are running"
else
  echo "❌ Some pods are not running"
  exit 1
fi

# Check data ingestion
echo "Checking data ingestion..."
METRICS_COUNT=$(kubectl exec -n kof vmselect-cluster-0 -- curl -s "http://localhost:8481/api/v1/query?query=up" | jq '.data.result | length')
if [ "$METRICS_COUNT" -gt 0 ]; then
  echo "✅ Metrics ingestion working ($METRICS_COUNT active targets)"
else
  echo "❌ No metrics found"
  exit 1
fi

# Check Grafana accessibility
echo "Checking Grafana..."
if kubectl exec -n kof grafana-vm-0 -- curl -s http://localhost:3000/api/health | grep -q "ok"; then
  echo "✅ Grafana is healthy"
else
  echo "❌ Grafana health check failed"
  exit 1
fi

# Check Jaeger
echo "Checking Jaeger..."
if kubectl exec -n kof jaeger-operator-0 -- curl -s http://localhost:14269/api/traces | grep -q "traces"; then
  echo "✅ Jaeger is healthy"
else
  echo "❌ Jaeger health check failed"
  exit 1
fi

echo "✅ All health checks passed!"
```

## 🔍 Troubleshooting

### Common Production Issues

#### Issue: High Memory Usage in VictoriaMetrics

```bash
# Diagnosis
kubectl top pods -n kof | grep vmstorage
kubectl exec -n kof vmstorage-cluster-0 -- /vmstorage-prod -version

# Solution: Increase memory limits and optimize retention
kubectl patch statefulset vmstorage-cluster -n kof -p='
{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "vmstorage",
          "resources": {
            "limits": {
              "memory": "4Gi"
            }
          }
        }]
      }
    }
  }
}'
```

#### Issue: Grafana Dashboard Loading Slowly

```bash
# Diagnosis
kubectl exec -n kof grafana-vm-0 -- curl -s "http://localhost:3000/api/admin/stats" | jq

# Solution: Scale Grafana and optimize queries
kubectl scale deployment grafana-vm --replicas=3 -n kof
```

#### Issue: Missing Metrics from Child Clusters

```bash
# Diagnosis
kubectl logs -l app.kubernetes.io/name=opentelemetry-collector -n kof --tail=100

# Check connectivity
kubectl exec -n kof collectors-node-0 -- curl -v https://vmauth.yourdomain.com/vm/api/v1/write

# Solution: Verify credentials and network connectivity
kubectl get secret storage-vmuser-credentials -n kof -o yaml
```

### Emergency Procedures

#### Complete System Recovery

```bash
#!/bin/bash
# emergency-recovery.sh

echo "Starting emergency recovery procedure..."

# 1. Stop all data ingestion
kubectl scale deployment vminsert-cluster --replicas=0 -n kof

# 2. Assess damage
kubectl get events -n kof --sort-by=.metadata.creationTimestamp

# 3. Restore from backup
./disaster-recovery.sh latest

# 4. Gradually restore services
kubectl scale deployment vminsert-cluster --replicas=3 -n kof
kubectl scale deployment vmselect-cluster --replicas=3 -n kof

# 5. Verify system health
./health-check.sh

echo "Emergency recovery completed!"
```

## 📞 Support & Escalation

### Support Tiers

1. **Level 1**: Basic monitoring and alerting issues
2. **Level 2**: Configuration and deployment issues  
3. **Level 3**: Core component failures and data corruption

### Escalation Contacts

- **Platform Team**: platform-team@yourdomain.com
- **On-call Engineer**: +1-xxx-xxx-xxxx
- **Vendor Support**: k0rdent support channels

### Runbook Links

- [Component Failure Runbook](https://runbooks.yourdomain.com/kof/component-failure)
- [Data Loss Recovery](https://runbooks.yourdomain.com/kof/data-recovery)
- [Performance Issues](https://runbooks.yourdomain.com/kof/performance)
- [Security Incidents](https://runbooks.yourdomain.com/kof/security)

---

This production guide provides a comprehensive foundation for deploying and operating KOF in production environments. Customize configurations based on your specific requirements and infrastructure constraints. 
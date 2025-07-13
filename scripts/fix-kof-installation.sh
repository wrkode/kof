#!/bin/bash

# KOF Installation Fix Script
# Fixes common issues with existing KOF installations

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

NAMESPACE="kof"

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Fix OpenCost configuration
fix_opencost() {
    log_info "Fixing OpenCost configuration..."
    
    # Create a patch for the OpenCost configuration
    cat > /tmp/opencost-fix.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: kof-collectors-opencost
  namespace: $NAMESPACE
data:
  PROMETHEUS_SERVER_ENDPOINT: "http://vmselect-cluster:8481/select/0/prometheus"
  PROMETHEUS_USERNAME: ""
  PROMETHEUS_PASSWORD: ""
  CUSTOM_COST_ENABLED: "false"
  CLOUD_PROVIDER_API_KEY: ""
  CLUSTER_ID: "quickstart"
EOF
    
    # Apply the fix
    kubectl apply -f /tmp/opencost-fix.yaml || log_warning "Could not update OpenCost config"
    
    # Restart OpenCost pods
    if kubectl get deployment kof-collectors-opencost -n $NAMESPACE &>/dev/null; then
        log_info "Restarting OpenCost deployment..."
        kubectl rollout restart deployment/kof-collectors-opencost -n $NAMESPACE
        kubectl rollout status deployment/kof-collectors-opencost -n $NAMESPACE --timeout=120s || log_warning "OpenCost restart timed out"
    fi
    
    rm -f /tmp/opencost-fix.yaml
}

# Fix collector endpoints
fix_collectors() {
    log_info "Fixing collector configuration..."
    
    # Get the current collectors deployment and patch it
    if kubectl get deployment kof-collectors-k8s-cluster-collector -n $NAMESPACE &>/dev/null; then
        log_info "Restarting k8s cluster collector..."
        kubectl rollout restart deployment/kof-collectors-k8s-cluster-collector -n $NAMESPACE
    fi
    
    if kubectl get daemonset kof-collectors-node-exporter-collector -n $NAMESPACE &>/dev/null; then
        log_info "Restarting node exporter collector..."
        kubectl rollout restart daemonset/kof-collectors-node-exporter-collector -n $NAMESPACE
    fi
}

# Create basic dashboard
create_basic_dashboard() {
    log_info "Creating basic Kubernetes dashboard..."
    
    cat > /tmp/basic-dashboard.yaml <<EOF
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  namespace: $NAMESPACE
  name: kubernetes-overview
  labels:
    app: grafana
spec:
  folder: "General"
  instanceSelector:
    matchLabels:
      dashboards: grafana
  json: |
    {
      "dashboard": {
        "id": null,
        "title": "Kubernetes Overview",
        "tags": ["kubernetes"],
        "style": "dark",
        "timezone": "browser",
        "panels": [
          {
            "id": 1,
            "title": "Cluster Status",
            "type": "stat",
            "targets": [
              {
                "expr": "sum(up{job=~\"kube-state-metrics\"})",
                "refId": "A",
                "legendFormat": "Nodes Up"
              }
            ],
            "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
            "fieldConfig": {
              "defaults": {
                "color": {"mode": "palette-classic"},
                "custom": {"displayMode": "basic"},
                "unit": "short"
              }
            }
          },
          {
            "id": 2,
            "title": "Pod Status",
            "type": "stat",
            "targets": [
              {
                "expr": "sum(kube_pod_status_phase)",
                "refId": "A",
                "legendFormat": "Total Pods"
              }
            ],
            "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
            "fieldConfig": {
              "defaults": {
                "color": {"mode": "palette-classic"},
                "custom": {"displayMode": "basic"},
                "unit": "short"
              }
            }
          }
        ],
        "time": {"from": "now-1h", "to": "now"},
        "refresh": "30s"
      }
    }
---
EOF
    
    kubectl apply -f /tmp/basic-dashboard.yaml || log_warning "Could not create basic dashboard"
    rm -f /tmp/basic-dashboard.yaml
}

# Verify data flow
verify_data_flow() {
    log_info "Verifying data flow..."
    
    # Check if VictoriaMetrics is receiving data
    local vm_endpoint="http://localhost:8481"
    if kubectl port-forward svc/vmselect-cluster 8481:8481 -n $NAMESPACE >/dev/null 2>&1 &
    then
        local port_forward_pid=$!
        sleep 3
        
        # Test if we can query metrics
        if curl -s "$vm_endpoint/select/0/prometheus/api/v1/query?query=up" | grep -q "success"; then
            log_success "VictoriaMetrics is receiving data"
        else
            log_warning "VictoriaMetrics may not be receiving data properly"
        fi
        
        kill $port_forward_pid 2>/dev/null || true
    fi
}

# Main execution
main() {
    echo "======================================================================"
    echo "KOF Installation Fix"
    echo "======================================================================"
    
    # Check if namespace exists
    if ! kubectl get namespace $NAMESPACE &>/dev/null; then
        log_error "Namespace $NAMESPACE does not exist"
        exit 1
    fi
    
    # Check if KOF is installed
    local kof_deployments=$(kubectl get deployment -n $NAMESPACE 2>/dev/null | grep "kof-" | wc -l || echo "0")
    if [[ "$kof_deployments" -eq 0 ]]; then
        log_error "No KOF installation found in namespace $NAMESPACE"
        exit 1
    fi
    
    log_info "Found $kof_deployments KOF deployments"
    
    fix_opencost
    fix_collectors
    create_basic_dashboard
    verify_data_flow
    
    log_success "KOF installation fix completed!"
    echo ""
    echo "Next steps:"
    echo "1. Access Grafana:"
    echo "   kubectl port-forward svc/grafana-vm-service 3000:3000 -n $NAMESPACE"
    echo "   Then visit: http://localhost:3000"
    echo ""
    echo "2. Get Grafana credentials:"
    echo "   kubectl get secret grafana-admin-credentials -n $NAMESPACE -o jsonpath='{.data.GF_SECURITY_ADMIN_USER}' | base64 -d && echo"
    echo "   kubectl get secret grafana-admin-credentials -n $NAMESPACE -o jsonpath='{.data.GF_SECURITY_ADMIN_PASSWORD}' | base64 -d && echo"
    echo ""
    echo "3. Check component status:"
    echo "   kubectl get pods -n $NAMESPACE"
}

# Run main function
main "$@" 
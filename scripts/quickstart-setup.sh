#!/bin/bash

# KOF Quick Setup Script
# This script installs KOF on any Kubernetes cluster (k0s, k3s, AKS, GKE, EKS)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="kof"
TIMEOUT="300s"

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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        log_error "helm is not installed. Please install helm first."
        exit 1
    fi
    
    # Check cluster access
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot access Kubernetes cluster. Please check your kubectl configuration."
        exit 1
    fi
    
    # Check admin permissions
    if ! kubectl auth can-i create clusterrole --all-namespaces &> /dev/null; then
        log_error "You don't have cluster-admin permissions. Please ensure you have the necessary permissions."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Detect cluster type
detect_cluster_type() {
    log_info "Detecting cluster type..."
    
    # Check for k3s
    if kubectl get nodes -o yaml | grep -q "k3s.io"; then
        CLUSTER_TYPE="k3s"
        log_info "Detected k3s cluster"
        return
    fi
    
    # Check for k0s
    if kubectl get nodes -o yaml | grep -q "k0s.io"; then
        CLUSTER_TYPE="k0s"
        log_info "Detected k0s cluster"
        return
    fi
    
    # Check for cloud providers
    if kubectl get nodes -o yaml | grep -q "eks.amazonaws.com"; then
        CLUSTER_TYPE="eks"
        log_info "Detected EKS cluster"
        return
    fi
    
    if kubectl get nodes -o yaml | grep -q "gke.io"; then
        CLUSTER_TYPE="gke"
        log_info "Detected GKE cluster"
        return
    fi
    
    if kubectl get nodes -o yaml | grep -q "azure.com"; then
        CLUSTER_TYPE="aks"
        log_info "Detected AKS cluster"
        return
    fi
    
    # Default to generic
    CLUSTER_TYPE="generic"
    log_info "Using generic cluster configuration"
}

# Get storage class
get_storage_class() {
    log_info "Detecting storage class..."
    
    # Try to get default storage class
    DEFAULT_STORAGE_CLASS=$(kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null || echo "")
    
    # If no default, use first available
    if [ -z "$DEFAULT_STORAGE_CLASS" ]; then
        DEFAULT_STORAGE_CLASS=$(kubectl get storageclass -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    fi
    
    # Cluster-specific defaults
    case $CLUSTER_TYPE in
        "k0s")
            DEFAULT_STORAGE_CLASS="local-path"
            ;;
        "k3s")
            if [ -z "$DEFAULT_STORAGE_CLASS" ]; then
                DEFAULT_STORAGE_CLASS="local-path"
            fi
            ;;
    esac
    
    if [ -z "$DEFAULT_STORAGE_CLASS" ]; then
        log_warning "No storage class found. Some features may not work properly."
        DEFAULT_STORAGE_CLASS="default"
    else
        log_info "Using storage class: $DEFAULT_STORAGE_CLASS"
    fi
}

# Install dependencies
install_dependencies() {
    log_info "Installing dependencies..."
    
    # Install cert-manager
    log_info "Installing cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.4/cert-manager.yaml
    
    # Wait for cert-manager
    kubectl wait --for=condition=Available --timeout=$TIMEOUT deployment/cert-manager -n cert-manager
    log_success "cert-manager installed successfully"
    
    # Install ingress controller based on cluster type
    case $CLUSTER_TYPE in
        "k3s")
            log_info "k3s already has Traefik ingress controller"
            ;;
        "eks"|"gke"|"aks")
            log_info "Installing ingress-nginx for cloud provider..."
            kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml
            kubectl wait --for=condition=Available --timeout=$TIMEOUT deployment/ingress-nginx-controller -n ingress-nginx
            ;;
        *)
            log_info "Installing ingress-nginx for on-premises..."
            kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/baremetal/deploy.yaml
            kubectl wait --for=condition=Available --timeout=$TIMEOUT deployment/ingress-nginx-controller -n ingress-nginx
            ;;
    esac
    
    log_success "Dependencies installed successfully"
}

# Prepare for KOF installation
prepare_kof_installation() {
    log_info "Preparing for KOF installation..."
    
    # Note: We don't add OCI repositories, we install directly from them
    # This function exists for consistency but OCI registries don't need repo add
    
    log_success "KOF installation preparation completed"
}

# Generate values file
generate_values() {
    log_info "Generating configuration values..."
    
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

    # Add cluster-specific configurations
    case $CLUSTER_TYPE in
        "k3s")
            cat >> quickstart-values.yaml <<EOF

# k3s specific configuration
ingress:
  enabled: true
  className: traefik
  annotations:
    kubernetes.io/ingress.class: traefik
EOF
            ;;
        "eks")
            cat >> quickstart-values.yaml <<EOF

# EKS specific configuration
ingress:
  enabled: true
  className: nginx
  annotations:
    kubernetes.io/ingress.class: nginx
EOF
            ;;
        "gke")
            cat >> quickstart-values.yaml <<EOF

# GKE specific configuration
ingress:
  enabled: true
  className: nginx
  annotations:
    kubernetes.io/ingress.class: nginx
EOF
            ;;
        "aks")
            cat >> quickstart-values.yaml <<EOF

# AKS specific configuration
ingress:
  enabled: true
  className: nginx
  annotations:
    kubernetes.io/ingress.class: nginx
EOF
            ;;
    esac
    
    log_success "Configuration values generated: quickstart-values.yaml"
}

# Deploy KOF
deploy_kof() {
    log_info "Deploying KOF components..."
    
    # Deploy operators
    log_info "Installing KOF operators..."
    helm install kof-operators oci://ghcr.io/k0rdent/kof/charts/kof-operators -n $NAMESPACE --create-namespace --wait --timeout=$TIMEOUT
    log_success "KOF operators installed"
    
    # Deploy storage
    log_info "Installing KOF storage..."
    helm install kof-storage oci://ghcr.io/k0rdent/kof/charts/kof-storage -n $NAMESPACE -f quickstart-values.yaml --wait --timeout=$TIMEOUT
    log_success "KOF storage installed"
    
    # Deploy collectors
    log_info "Installing KOF collectors..."
    helm install kof-collectors oci://ghcr.io/k0rdent/kof/charts/kof-collectors -n $NAMESPACE -f quickstart-values.yaml --wait --timeout=$TIMEOUT
    log_success "KOF collectors installed"
    
    # Deploy mothership
    log_info "Installing KOF mothership..."
    helm install kof-mothership oci://ghcr.io/k0rdent/kof/charts/kof-mothership -n $NAMESPACE -f quickstart-values.yaml --wait --timeout=$TIMEOUT
    log_success "KOF mothership installed"
    
    log_success "KOF deployment completed successfully!"
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    # Check pods
    log_info "Checking pod status..."
    kubectl get pods -n $NAMESPACE
    
    # Check if all pods are running
    if kubectl get pods -n $NAMESPACE --no-headers | grep -v Running | grep -v Completed; then
        log_warning "Some pods are not running. Please check the pod status above."
    else
        log_success "All pods are running successfully"
    fi
    
    # Check services
    log_info "Checking services..."
    kubectl get svc -n $NAMESPACE
}

# Show access information
show_access_info() {
    log_info "Getting access information..."
    
    # Get Grafana credentials
    GRAFANA_USER=$(kubectl get secret grafana-admin-credentials -n $NAMESPACE -o jsonpath='{.data.GF_SECURITY_ADMIN_USER}' 2>/dev/null | base64 -d || echo "admin")
    GRAFANA_PASSWORD=$(kubectl get secret grafana-admin-credentials -n $NAMESPACE -o jsonpath='{.data.GF_SECURITY_ADMIN_PASSWORD}' 2>/dev/null | base64 -d || echo "admin")
    
    echo
    echo "======================================================================"
    echo "🎉 KOF Installation Complete!"
    echo "======================================================================"
    echo
    echo "Access your KOF deployment:"
    echo
    echo "1. Grafana Dashboard:"
    echo "   Port Forward: kubectl port-forward svc/grafana 3000:3000 -n $NAMESPACE"
    echo "   URL: http://localhost:3000"
    echo "   Username: $GRAFANA_USER"
    echo "   Password: $GRAFANA_PASSWORD"
    echo
    echo "2. KOF Operator UI:"
    echo "   Port Forward: kubectl port-forward svc/kof-mothership-kof-operator-ui 9090:9090 -n $NAMESPACE"
    echo "   URL: http://localhost:9090"
    echo
    echo "3. Jaeger UI:"
    echo "   Port Forward: kubectl port-forward svc/jaeger-query 16686:16686 -n $NAMESPACE"
    echo "   URL: http://localhost:16686"
    echo
    echo "4. VictoriaMetrics:"
    echo "   Port Forward: kubectl port-forward svc/vmselect-vmcluster 8481:8481 -n $NAMESPACE"
    echo "   URL: http://localhost:8481"
    echo
    echo "For production use, consider configuring ingress or LoadBalancer services."
    echo
    echo "For more information, visit: https://docs.k0rdent.io/next/admin/kof/"
    echo "======================================================================"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -f quickstart-values.yaml
}

# Main execution
main() {
    echo "======================================================================"
    echo "KOF Quick Setup Script"
    echo "======================================================================"
    echo
    
    # Trap cleanup on exit
    trap cleanup EXIT
    
    check_prerequisites
    detect_cluster_type
    get_storage_class
    install_dependencies
    prepare_kof_installation
    generate_values
    deploy_kof
    verify_installation
    show_access_info
    
    log_success "KOF setup completed successfully!"
}

# Run main function
main "$@" 
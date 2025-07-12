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
DEPLOYMENT_MODE="single"  # single, multi-cluster, regional, child
ENABLE_DNS="false"
ENABLE_ISTIO="false"
DNS_PROVIDER=""
DNS_DOMAIN=""
CLUSTER_ROLE="single"
REGIONAL_ENDPOINT=""

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

# Show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

KOF Installation Options:
  -m, --mode MODE          Deployment mode: single, multi-cluster, regional, child (default: single)
  -r, --cluster-role ROLE  Cluster role: management, regional, child (for multi-cluster)
  -e, --regional-endpoint  Regional cluster endpoint (for child clusters)
  
DNS Auto-Configuration:
  --enable-dns             Enable external-dns for automatic DNS management
  --dns-provider PROVIDER  DNS provider: aws, azure, google (requires --enable-dns)
  --dns-domain DOMAIN      Domain to manage (requires --enable-dns)
  
Service Mesh:
  --enable-istio           Enable Istio service mesh integration
  
General Options:
  -n, --namespace NAME     Kubernetes namespace (default: kof)
  -t, --timeout DURATION  Installation timeout (default: 300s)
  -h, --help               Show this help message

Examples:
  # Single cluster installation (default)
  $0

  # Multi-cluster with DNS auto-config
  $0 --mode multi-cluster --cluster-role management --enable-dns --dns-provider aws --dns-domain example.com

  # Regional cluster
  $0 --mode multi-cluster --cluster-role regional --enable-istio

  # Child cluster
  $0 --mode multi-cluster --cluster-role child --regional-endpoint https://regional.example.com

  # Single cluster with Istio
  $0 --enable-istio

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--mode)
                DEPLOYMENT_MODE="$2"
                shift 2
                ;;
            -r|--cluster-role)
                CLUSTER_ROLE="$2"
                shift 2
                ;;
            -e|--regional-endpoint)
                REGIONAL_ENDPOINT="$2"
                shift 2
                ;;
            --enable-dns)
                ENABLE_DNS="true"
                shift
                ;;
            --dns-provider)
                DNS_PROVIDER="$2"
                shift 2
                ;;
            --dns-domain)
                DNS_DOMAIN="$2"
                shift 2
                ;;
            --enable-istio)
                ENABLE_ISTIO="true"
                shift
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Validate arguments
    if [[ "$DEPLOYMENT_MODE" == "multi-cluster" && -z "$CLUSTER_ROLE" ]]; then
        log_error "Multi-cluster mode requires --cluster-role to be set"
        exit 1
    fi

    if [[ "$CLUSTER_ROLE" == "child" && -z "$REGIONAL_ENDPOINT" ]]; then
        log_error "Child clusters require --regional-endpoint to be set"
        exit 1
    fi

    if [[ "$ENABLE_DNS" == "true" && (-z "$DNS_PROVIDER" || -z "$DNS_DOMAIN") ]]; then
        log_error "DNS auto-configuration requires --dns-provider and --dns-domain"
        exit 1
    fi
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

    # Check Istio if enabled
    if [[ "$ENABLE_ISTIO" == "true" ]]; then
        if ! command -v istioctl &> /dev/null; then
            log_warning "istioctl not found. Istio will be installed automatically."
        fi
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
    
    # Install Istio if enabled
    if [[ "$ENABLE_ISTIO" == "true" ]]; then
        install_istio
    fi
    
    # Install ingress controller based on cluster type (skip if Istio handles ingress)
    if [[ "$ENABLE_ISTIO" != "true" ]]; then
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
    fi
    
    log_success "Dependencies installed successfully"
}

# Install Istio
install_istio() {
    log_info "Installing Istio service mesh..."
    
    # Check if Istio is already installed
    if kubectl get namespace istio-system &> /dev/null; then
        log_info "Istio namespace already exists, skipping installation"
        return
    fi
    
    # Download and install Istio
    if ! command -v istioctl &> /dev/null; then
        log_info "Downloading Istio..."
        curl -L https://istio.io/downloadIstio | sh -
        export PATH=$PWD/istio-*/bin:$PATH
    fi
    
    # Install Istio
    log_info "Installing Istio control plane..."
    istioctl install --set values.defaultRevision=default -y
    
    # Create and label KOF namespace for Istio injection
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace "$NAMESPACE" istio-injection=enabled --overwrite
    
    log_success "Istio installed successfully"
}

# Setup DNS auto-configuration
setup_dns_auto_config() {
    if [[ "$ENABLE_DNS" != "true" ]]; then
        return
    fi
    
    log_info "Setting up DNS auto-configuration for $DNS_PROVIDER..."
    
    case $DNS_PROVIDER in
        "aws")
            setup_aws_dns
            ;;
        "azure")
            setup_azure_dns
            ;;
        "google")
            setup_google_dns
            ;;
        *)
            log_error "Unsupported DNS provider: $DNS_PROVIDER"
            exit 1
            ;;
    esac
    
    log_success "DNS auto-configuration setup completed"
}

# Setup AWS Route53 DNS
setup_aws_dns() {
    log_info "Setting up AWS Route53 DNS..."
    
    # Check if credentials are provided via environment or AWS CLI
    if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" ]]; then
        log_warning "AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables not set"
        log_warning "Please ensure AWS credentials are configured via:"
        log_warning "1. Environment variables"
        log_warning "2. AWS CLI configuration"
        log_warning "3. IAM roles (for EKS)"
        return
    fi
    
    # Create credentials file
    cat > /tmp/external-dns-aws-credentials <<EOF
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF
    
    # Create secret
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic external-dns-aws-credentials -n "$NAMESPACE" \
        --from-file=/tmp/external-dns-aws-credentials --dry-run=client -o yaml | kubectl apply -f -
    
    # Clean up credentials file
    rm -f /tmp/external-dns-aws-credentials
    
    log_success "AWS DNS credentials configured"
}

# Setup Azure DNS
setup_azure_dns() {
    log_info "Setting up Azure DNS..."
    
    # Check if Azure credentials are provided
    if [[ -z "$AZURE_TENANT_ID" || -z "$AZURE_SUBSCRIPTION_ID" || -z "$AZURE_CLIENT_ID" || -z "$AZURE_CLIENT_SECRET" ]]; then
        log_warning "Azure credentials not set. Please set the following environment variables:"
        log_warning "AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET"
        return
    fi
    
    # Create azure.json
    cat > /tmp/azure.json <<EOF
{
  "tenantId": "$AZURE_TENANT_ID",
  "subscriptionId": "$AZURE_SUBSCRIPTION_ID",
  "resourceGroup": "$AZURE_RESOURCE_GROUP",
  "aadClientId": "$AZURE_CLIENT_ID",
  "aadClientSecret": "$AZURE_CLIENT_SECRET"
}
EOF
    
    # Create secret
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic external-dns-azure-credentials -n "$NAMESPACE" \
        --from-file=/tmp/azure.json --dry-run=client -o yaml | kubectl apply -f -
    
    # Clean up credentials file
    rm -f /tmp/azure.json
    
    log_success "Azure DNS credentials configured"
}

# Setup Google Cloud DNS
setup_google_dns() {
    log_info "Setting up Google Cloud DNS..."
    
    # Check if Google Cloud credentials are provided
    if [[ -z "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
        log_warning "GOOGLE_APPLICATION_CREDENTIALS environment variable not set"
        log_warning "Please set it to point to your service account key file"
        return
    fi
    
    # Create secret from service account file
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    kubectl create secret generic external-dns-google-credentials -n "$NAMESPACE" \
        --from-file="$GOOGLE_APPLICATION_CREDENTIALS" --dry-run=client -o yaml | kubectl apply -f -
    
    log_success "Google DNS credentials configured"
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
    
    # Base configuration
    cat > quickstart-values.yaml <<EOF
global:
  clusterName: $CLUSTER_ROLE
  storageClass: "$DEFAULT_STORAGE_CLASS"
EOF

    # Add deployment mode specific configuration
    case $DEPLOYMENT_MODE in
        "single")
            generate_single_cluster_values
            ;;
        "multi-cluster")
            generate_multi_cluster_values
            ;;
    esac
    
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
        "eks"|"gke"|"aks")
            if [[ "$ENABLE_ISTIO" != "true" ]]; then
                cat >> quickstart-values.yaml <<EOF

# Cloud provider configuration
ingress:
  enabled: true
  className: nginx
  annotations:
    kubernetes.io/ingress.class: nginx
EOF
            fi
            ;;
    esac
    
    # Add DNS configuration if enabled
    if [[ "$ENABLE_DNS" == "true" ]]; then
        cat >> quickstart-values.yaml <<EOF

# DNS auto-configuration
external-dns:
  enabled: true
  provider: $DNS_PROVIDER
  domainFilters:
    - $DNS_DOMAIN
  policy: sync
EOF
    fi
    
    # Add Istio configuration if enabled
    if [[ "$ENABLE_ISTIO" == "true" ]]; then
        cat >> quickstart-values.yaml <<EOF

# Istio service mesh configuration
istio:
  enabled: true
  multiCluster:
    clusterName: $CLUSTER_ROLE
    network: ${CLUSTER_ROLE}-network
  gateway:
    enabled: true
EOF
    fi
    
    log_success "Configuration values generated: quickstart-values.yaml"
}

# Generate single cluster values
generate_single_cluster_values() {
    cat >> quickstart-values.yaml <<EOF

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

# Use NodePort for easy access on any cluster
service:
  type: NodePort
EOF
}

# Generate multi-cluster values
generate_multi_cluster_values() {
    case $CLUSTER_ROLE in
        "management")
            cat >> quickstart-values.yaml <<EOF

# Management cluster configuration
grafana:
  enabled: true
  security:
    create_secret: true
  persistence:
    enabled: true
    size: 10Gi

victoriametrics:
  enabled: false

jaeger:
  enabled: false

dex:
  enabled: true
EOF
            ;;
        "regional")
            cat >> quickstart-values.yaml <<EOF

# Regional cluster configuration  
grafana:
  enabled: false

victoriametrics:
  enabled: true
  vmcluster:
    enabled: true
    replicationFactor: 2
    replicaCount: 2

jaeger:
  enabled: true
  storage:
    type: elasticsearch

dex:
  enabled: false
EOF
            ;;
        "child")
            cat >> quickstart-values.yaml <<EOF

# Child cluster configuration
grafana:
  enabled: false

victoriametrics:
  enabled: false

jaeger:
  enabled: false

dex:
  enabled: false

# Configure endpoints to regional cluster
kof:
  endpoints:
    metrics:
      write: "$REGIONAL_ENDPOINT/vm/insert/0/prometheus/api/v1/write"
    logs:
      write: "$REGIONAL_ENDPOINT/vli/insert/opentelemetry/v1/logs"
    traces:
      write: "$REGIONAL_ENDPOINT/collector"
EOF
            ;;
    esac
}

# Deploy KOF
deploy_kof() {
    log_info "Deploying KOF components for $DEPLOYMENT_MODE mode..."
    
    case $DEPLOYMENT_MODE in
        "single")
            deploy_single_cluster
            ;;
        "multi-cluster")
            deploy_multi_cluster
            ;;
    esac
    
    log_success "KOF deployment completed successfully!"
}

# Deploy single cluster
deploy_single_cluster() {
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
}

# Deploy multi-cluster
deploy_multi_cluster() {
    case $CLUSTER_ROLE in
        "management")
            log_info "Installing KOF mothership for management cluster..."
            helm install kof-operators oci://ghcr.io/k0rdent/kof/charts/kof-operators -n $NAMESPACE --create-namespace --wait --timeout=$TIMEOUT
            helm install kof-mothership oci://ghcr.io/k0rdent/kof/charts/kof-mothership -n $NAMESPACE -f quickstart-values.yaml --wait --timeout=$TIMEOUT
            log_success "KOF management components installed"
            ;;
        "regional")
            log_info "Installing KOF storage for regional cluster..."
            helm install kof-operators oci://ghcr.io/k0rdent/kof/charts/kof-operators -n $NAMESPACE --create-namespace --wait --timeout=$TIMEOUT
            helm install kof-storage oci://ghcr.io/k0rdent/kof/charts/kof-storage -n $NAMESPACE -f quickstart-values.yaml --wait --timeout=$TIMEOUT
            log_success "KOF regional components installed"
            ;;
        "child")
            log_info "Installing KOF collectors for child cluster..."
            helm install kof-operators oci://ghcr.io/k0rdent/kof/charts/kof-operators -n $NAMESPACE --create-namespace --wait --timeout=$TIMEOUT
            helm install kof-collectors oci://ghcr.io/k0rdent/kof/charts/kof-collectors -n $NAMESPACE -f quickstart-values.yaml --wait --timeout=$TIMEOUT
            log_success "KOF child components installed"
            ;;
    esac

    # Deploy Istio configuration if enabled
    if [[ "$ENABLE_ISTIO" == "true" ]]; then
        log_info "Installing KOF Istio configuration..."
        helm install kof-istio oci://ghcr.io/k0rdent/kof/charts/kof-istio -n istio-system -f quickstart-values.yaml --wait --timeout=$TIMEOUT
        log_success "KOF Istio configuration installed"
    fi
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

    # Check ingress if not using Istio
    if [[ "$ENABLE_ISTIO" != "true" ]]; then
        log_info "Checking ingress..."
        kubectl get ingress -n $NAMESPACE
    fi

    # Check Istio resources if enabled
    if [[ "$ENABLE_ISTIO" == "true" ]]; then
        log_info "Checking Istio configuration..."
        kubectl get gateway,virtualservice -n $NAMESPACE
    fi
}

# Show access information
show_access_info() {
    log_info "Getting access information..."
    
    # Get Grafana credentials (only for single cluster or management cluster)
    if [[ "$DEPLOYMENT_MODE" == "single" || "$CLUSTER_ROLE" == "management" ]]; then
        GRAFANA_USER=$(kubectl get secret grafana-admin-credentials -n $NAMESPACE -o jsonpath='{.data.GF_SECURITY_ADMIN_USER}' 2>/dev/null | base64 -d || echo "admin")
        GRAFANA_PASSWORD=$(kubectl get secret grafana-admin-credentials -n $NAMESPACE -o jsonpath='{.data.GF_SECURITY_ADMIN_PASSWORD}' 2>/dev/null | base64 -d || echo "admin")
    fi
    
    echo
    echo "======================================================================"
    echo "🎉 KOF Installation Complete!"
    echo "======================================================================"
    echo
    echo "Deployment Configuration:"
    echo "  Mode: $DEPLOYMENT_MODE"
    echo "  Cluster Role: $CLUSTER_ROLE"
    echo "  Namespace: $NAMESPACE"
    echo "  Storage Class: $DEFAULT_STORAGE_CLASS"
    echo "  DNS Auto-Config: $ENABLE_DNS"
    echo "  Istio Enabled: $ENABLE_ISTIO"
    echo
    
    if [[ "$DEPLOYMENT_MODE" == "single" || "$CLUSTER_ROLE" == "management" ]]; then
        echo "Access your KOF deployment:"
        echo
        echo "1. Grafana Dashboard:"
        echo "   Port Forward: kubectl port-forward svc/grafana 3000:3000 -n $NAMESPACE"
        echo "   URL: http://localhost:3000"
        echo "   Username: $GRAFANA_USER"
        echo "   Password: $GRAFANA_PASSWORD"
        echo
    fi
    
    if [[ "$DEPLOYMENT_MODE" == "single" ]]; then
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
    fi
    
    if [[ "$ENABLE_DNS" == "true" ]]; then
        echo "DNS Configuration:"
        echo "  Provider: $DNS_PROVIDER"
        echo "  Domain: $DNS_DOMAIN"
        echo "  Check external-dns logs: kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=external-dns"
        echo
    fi
    
    if [[ "$ENABLE_ISTIO" == "true" ]]; then
        echo "Istio Configuration:"
        echo "  Gateway: kubectl get gateway -n $NAMESPACE"
        echo "  VirtualServices: kubectl get virtualservice -n $NAMESPACE"
        echo "  Check Istio: istioctl analyze -n $NAMESPACE"
        echo
    fi
    
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
    
    parse_args "$@"
    check_prerequisites
    detect_cluster_type
    get_storage_class
    setup_dns_auto_config
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
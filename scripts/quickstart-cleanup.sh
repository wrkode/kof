#!/bin/bash

# KOF Quick Cleanup Script
# This script removes KOF and its dependencies installed by quickstart-setup.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="kof"
FORCE_CLEANUP=false

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

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_CLEANUP=true
                shift
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  -f, --force      Force cleanup without confirmation"
                echo "  -n, --namespace  Specify KOF namespace (default: kof)"
                echo "  -h, --help       Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# Confirm cleanup
confirm_cleanup() {
    if [ "$FORCE_CLEANUP" = true ]; then
        return 0
    fi
    
    echo
    echo "======================================================================"
    echo "KOF Cleanup Confirmation"
    echo "======================================================================"
    echo
    echo "This will remove:"
    echo "  - All KOF components from namespace '$NAMESPACE'"
    echo "  - KOF Helm releases (including Istio configuration)"
    echo "  - KOF persistent volumes and data"
    echo "  - cert-manager (if no other workloads depend on it)"
    echo "  - ingress-nginx (if no other workloads depend on it)"
    echo "  - Istio service mesh (if no other workloads depend on it)"
    echo
    echo "⚠️  WARNING: This will permanently delete all KOF data and configurations!"
    echo
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Remove KOF components
remove_kof_components() {
    log_info "Removing KOF components..."
    
    # List of KOF Helm releases in reverse installation order
    KOF_RELEASES=("kof-mothership" "kof-collectors" "kof-storage" "kof-operators" "kof-istio")
    
    for release in "${KOF_RELEASES[@]}"; do
        # Check both kof namespace and istio-system namespace for kof-istio
        if [ "$release" = "kof-istio" ]; then
            if helm list -n istio-system | grep -q "$release"; then
                log_info "Removing Helm release: $release (from istio-system)"
                helm uninstall "$release" -n istio-system || log_warning "Failed to remove $release"
            fi
        else
            if helm list -n "$NAMESPACE" | grep -q "$release"; then
                log_info "Removing Helm release: $release"
                helm uninstall "$release" -n "$NAMESPACE" || log_warning "Failed to remove $release"
            else
                log_info "Helm release $release not found, skipping"
            fi
        fi
    done
    
    log_success "KOF components removal completed"
}

# Remove KOF namespace and resources
remove_kof_namespace() {
    log_info "Removing KOF namespace and resources..."
    
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        # Remove KOF-specific secrets first
        log_info "Removing KOF secrets..."
        kubectl delete secret dex-tls -n "$NAMESPACE" --ignore-not-found=true || true
        kubectl delete secret grafana-admin-credentials -n "$NAMESPACE" --ignore-not-found=true || true
        
        # Remove any finalizers that might block deletion
        log_info "Removing finalizers from KOF resources..."
        kubectl patch pvc -n "$NAMESPACE" --all -p '{"metadata":{"finalizers":null}}' --type=merge || true
        kubectl patch pv --all -p '{"metadata":{"finalizers":null}}' --type=merge || true
        
        # Delete the namespace
        log_info "Deleting namespace: $NAMESPACE"
        kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
        
        # Wait for namespace deletion
        log_info "Waiting for namespace deletion..."
        timeout=60
        while kubectl get namespace "$NAMESPACE" &> /dev/null && [ $timeout -gt 0 ]; do
            sleep 2
            timeout=$((timeout - 2))
        done
        
        if kubectl get namespace "$NAMESPACE" &> /dev/null; then
            log_warning "Namespace $NAMESPACE still exists after timeout"
        else
            log_success "Namespace $NAMESPACE deleted successfully"
        fi
    else
        log_info "Namespace $NAMESPACE not found, skipping"
    fi
}

# Remove KOF Custom Resource Definitions
remove_kof_crds() {
    log_info "Removing KOF Custom Resource Definitions..."
    
    # List of KOF-related CRDs
    KOF_CRDS=(
        "promxyservergroups.kof.k0rdent.mirantis.com"
        "opentelemetrycollectors.opentelemetry.io"
        "instrumentations.opentelemetry.io"
        "servicemonitors.monitoring.coreos.com"
        "prometheusrules.monitoring.coreos.com"
    )
    
    for crd in "${KOF_CRDS[@]}"; do
        if kubectl get crd "$crd" &> /dev/null; then
            log_info "Removing CRD: $crd"
            kubectl delete crd "$crd" --ignore-not-found=true
        fi
    done
    
    # Remove Istio CRDs if they exist and no other Istio workloads
    if check_istio_dependencies; then
        log_info "Removing Istio CRDs..."
        kubectl get crd | grep "istio.io" | awk '{print $1}' | xargs -r kubectl delete crd
    else
        log_warning "Istio CRDs are in use by other workloads, skipping removal"
    fi
    
    log_success "KOF CRDs removal completed"
}

# Check if other workloads depend on cert-manager
check_cert_manager_dependencies() {
    local cert_manager_namespaces
    cert_manager_namespaces=$(kubectl get certificates,issuers,clusterissuers --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null | sort -u | grep -v "^cert-manager$" | grep -v "^$NAMESPACE$" || true)
    
    if [ -n "$cert_manager_namespaces" ]; then
        log_warning "cert-manager is being used by other namespaces: $cert_manager_namespaces"
        return 1
    fi
    return 0
}

# Check if other workloads depend on Istio
check_istio_dependencies() {
    local istio_namespaces
    istio_namespaces=$(kubectl get namespace -l istio-injection=enabled -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | grep -v "^$NAMESPACE$" || true)
    
    if [ -n "$istio_namespaces" ]; then
        log_warning "Istio is being used by other namespaces: $istio_namespaces"
        return 1
    fi
    
    # Check for other Istio resources
    local other_istio_resources
    other_istio_resources=$(kubectl get gateway,virtualservice,destinationrule,serviceentry --all-namespaces --no-headers 2>/dev/null | grep -v "^$NAMESPACE" | wc -l || echo "0")
    
    if [ "$other_istio_resources" -gt 0 ]; then
        log_warning "Istio resources are being used by other namespaces"
        return 1
    fi
    
    return 0
}

# Remove cert-manager
remove_cert_manager() {
    log_info "Checking cert-manager dependencies..."
    
    if check_cert_manager_dependencies; then
        log_info "No other workloads depend on cert-manager, removing it..."
        kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.4/cert-manager.yaml --ignore-not-found=true
        log_success "cert-manager removed"
    else
        log_warning "cert-manager is in use by other workloads, skipping removal"
    fi
}

# Check if other workloads depend on ingress-nginx
check_ingress_dependencies() {
    local ingress_count
    ingress_count=$(kubectl get ingress --all-namespaces --no-headers 2>/dev/null | grep -v "^$NAMESPACE" | wc -l || echo "0")
    
    if [ "$ingress_count" -gt 0 ]; then
        log_warning "ingress-nginx is being used by $ingress_count other ingresses"
        return 1
    fi
    return 0
}

# Remove ingress controller
remove_ingress_controller() {
    log_info "Checking ingress controller dependencies..."
    
    if check_ingress_dependencies; then
        log_info "No other workloads depend on ingress controller, removing it..."
        
        # Try to remove ingress-nginx
        kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml --ignore-not-found=true || \
        kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/baremetal/deploy.yaml --ignore-not-found=true || \
        log_info "ingress-nginx manifests not found (may not have been installed)"
        
        log_success "ingress controller removal completed"
    else
        log_warning "ingress controller is in use by other workloads, skipping removal"
    fi
}

# Remove Istio
remove_istio() {
    log_info "Checking Istio dependencies..."
    
    if check_istio_dependencies; then
        log_info "No other workloads depend on Istio, removing it..."
        
        # Check if istioctl is available
        if command -v istioctl &> /dev/null; then
            log_info "Uninstalling Istio using istioctl..."
            istioctl uninstall --purge -y || log_warning "Failed to uninstall Istio with istioctl"
        else
            log_info "istioctl not found, removing Istio resources manually..."
            kubectl delete namespace istio-system --ignore-not-found=true
        fi
        
        # Remove Istio injection label from our namespace
        kubectl label namespace "$NAMESPACE" istio-injection- --ignore-not-found=true
        
        log_success "Istio removal completed"
    else
        log_warning "Istio is in use by other workloads, skipping removal"
    fi
}

# Clean up persistent volumes
cleanup_persistent_volumes() {
    log_info "Cleaning up orphaned persistent volumes..."
    
    # Find PVs that were bound to the KOF namespace
    local orphaned_pvs
    orphaned_pvs=$(kubectl get pv -o jsonpath='{range .items[?(@.spec.claimRef.namespace=="'$NAMESPACE'")]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
    
    if [ -n "$orphaned_pvs" ]; then
        log_info "Found orphaned persistent volumes:"
        echo "$orphaned_pvs"
        
        for pv in $orphaned_pvs; do
            log_info "Removing persistent volume: $pv"
            kubectl patch pv "$pv" -p '{"metadata":{"finalizers":null}}' --type=merge || true
            kubectl delete pv "$pv" --ignore-not-found=true || true
        done
    else
        log_info "No orphaned persistent volumes found"
    fi
    
    log_success "Persistent volume cleanup completed"
}

# Show cleanup summary
show_cleanup_summary() {
    echo
    echo "======================================================================"
    echo "🧹 KOF Cleanup Complete!"
    echo "======================================================================"
    echo
    echo "Removed components:"
    echo "  ✅ KOF Helm releases (mothership, collectors, storage, operators, istio)"
    echo "  ✅ KOF namespace ($NAMESPACE)"
    echo "  ✅ KOF Custom Resource Definitions"
    echo "  ✅ Orphaned persistent volumes"
    echo
    echo "Dependencies:"
    echo "  📋 cert-manager: $(kubectl get namespace cert-manager &>/dev/null && echo "Still installed (in use by other workloads)" || echo "Removed")"
    echo "  📋 ingress-nginx: $(kubectl get namespace ingress-nginx &>/dev/null && echo "Still installed (in use by other workloads)" || echo "Removed")"
    echo "  📋 Istio: $(kubectl get namespace istio-system &>/dev/null && echo "Still installed (in use by other workloads)" || echo "Removed")"
    echo
    echo "Your cluster is now clean and ready for fresh KOF installation!"
    echo "To reinstall with advanced features:"
    echo "  ./scripts/quickstart-setup.sh --help"
    echo "======================================================================"
}

# Main execution
main() {
    echo "======================================================================"
    echo "KOF Quick Cleanup Script"
    echo "======================================================================"
    echo
    
    parse_args "$@"
    confirm_cleanup
    
    log_info "Starting KOF cleanup process..."
    echo
    
    remove_kof_components
    remove_kof_namespace
    remove_kof_crds
    cleanup_persistent_volumes
    remove_cert_manager
    remove_ingress_controller
    remove_istio
    
    show_cleanup_summary
    
    log_success "KOF cleanup completed successfully!"
}

# Run main function
main "$@" 
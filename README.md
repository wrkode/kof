# k0rdent Observability and FinOps (KOF)

[![Go Report Card](https://goreportcard.com/badge/github.com/k0rdent/kof)](https://goreportcard.com/report/github.com/k0rdent/kof)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Release](https://img.shields.io/github/release/k0rdent/kof.svg)](https://github.com/k0rdent/kof/releases/latest)

KOF is a comprehensive Kubernetes observability and FinOps platform built on top of [k0rdent/kcm](https://github.com/k0rdent/kcm). It provides unified monitoring, logging, tracing, and cost management across multi-cluster Kubernetes environments.

## 🚀 Key Features

- **🔍 Complete Observability Stack**: Metrics, logs, and traces with VictoriaMetrics, Grafana, and Jaeger
- **🌐 Multi-Cluster Management**: Seamless monitoring across regional and child clusters
- **💰 FinOps Integration**: Cost tracking and optimization with OpenCost
- **🔒 Security-First**: Built-in authentication with Dex SSO, RBAC, and optional Istio service mesh
- **⚡ Production-Ready**: High availability, scalability, and comprehensive monitoring
- **🛠️ Cloud Native**: Helm charts, Kubernetes operators, and modern web UI

## 🏗️ Architecture

KOF follows a hub-and-spoke architecture with three cluster types:

- **Mothership**: Central management cluster running the KOF operator and Grafana
- **Regional**: Storage clusters for metrics, logs, and traces
- **Child**: Workload clusters with data collectors

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Mothership    │    │    Regional     │    │     Child       │
│                 │    │                 │    │                 │
│ • KOF Operator  │◄──►│ • VictoriaMetrics│◄──►│ • Collectors    │
│ • Grafana       │    │ • Victoria Logs │    │ • Node Exporter │
│ • Promxy        │    │ • Jaeger        │    │ • OpenCost      │
│ • Web UI        │    │ • Dex (optional)│    │ • Applications  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 📚 Documentation

| Topic | Description | Link |
|-------|-------------|------|
| **Installation** | Production installation guide | [INSTALL.md](docs/INSTALL.md) |
| **Quick Start** | Get started in 15 minutes | [QUICKSTART.md](docs/QUICKSTART.md) |
| **Development** | Development setup and workflows | [docs/dev.md](docs/dev.md) |
| **Security** | Security configuration and best practices | [SECURITY.md](docs/SECURITY.md) |
| **Architecture** | Detailed architecture and component overview | [docs/README.md](docs/README.md) |
| **Production** | Production deployment and operations | [PRODUCTION.md](docs/PRODUCTION.md) |

### Feature Documentation

- [Istio Service Mesh](docs/istio.md) - Secure multi-cluster communication
- [Traces](docs/traces.md) - Distributed tracing with Jaeger
- [Dex SSO](docs/dex-sso.md) - Single sign-on configuration
- [Collectors](docs/collectors.md) - OpenTelemetry collector customization
- [System Requirements](docs/system-requirements.md) - Hardware and resource planning
- [Release Process](docs/release.md) - Release management and versioning

## 🚀 Quick Start

### Prerequisites

- **Kubernetes 1.19+ cluster** (k0s, k3s, AKS, GKE, EKS, etc.)
- **Helm 3.0+** installed
- **kubectl** configured for your cluster
- **Admin permissions** on the cluster

### One-Command Setup

Get KOF running in 15 minutes on any Kubernetes cluster:

```bash
# Clone the repository
git clone https://github.com/k0rdent/kof.git
cd kof

# Single cluster setup (default)
./scripts/quickstart-setup.sh

# Multi-cluster with Istio and DNS auto-config
./scripts/quickstart-setup.sh --mode multi-cluster --cluster-role management --enable-istio --enable-dns --dns-provider aws --dns-domain example.com

# View all options
./scripts/quickstart-setup.sh --help
```

This script automatically:
- Detects your cluster type (k0s, k3s, AKS, GKE, EKS)
- Installs required dependencies (cert-manager, ingress controller, Istio)
- Supports single-cluster and multi-cluster deployments
- Configures DNS auto-management (AWS Route53, Azure DNS, Google Cloud DNS)
- Enables Istio service mesh for secure multi-cluster communication
- Deploys KOF components with optimal configuration
- Provides comprehensive access instructions

### Manual Setup

For detailed step-by-step instructions, see our [Quick Start Guide](docs/QUICKSTART.md).

### Production Installation

For production deployments, see our [Production Guide](docs/PRODUCTION.md) with security hardening, high availability, and scaling configurations.

## 🧩 Components

### Core Components

| Component | Description | Chart |
|-----------|-------------|-------|
| **kof-mothership** | Central management and UI | [charts/kof-mothership](charts/kof-mothership) |
| **kof-storage** | Metrics, logs, and traces storage | [charts/kof-storage](charts/kof-storage) |
| **kof-collectors** | Data collection and forwarding | [charts/kof-collectors](charts/kof-collectors) |
| **kof-operator** | Kubernetes operator for automation | [kof-operator/](kof-operator) |

### Optional Components

| Component | Description | Chart |
|-----------|-------------|-------|
| **kof-istio** | Service mesh integration | [charts/kof-istio](charts/kof-istio) |
| **kof-regional** | Regional cluster configuration | [charts/kof-regional](charts/kof-regional) |
| **kof-child** | Child cluster configuration | [charts/kof-child](charts/kof-child) |

## 🔧 Technology Stack

- **Backend**: Go 1.24+, Kubernetes Operator SDK
- **Frontend**: React 19, TypeScript, Vite, TailwindCSS
- **Monitoring**: VictoriaMetrics, Grafana, Prometheus
- **Logging**: Victoria Logs, OpenTelemetry
- **Tracing**: Jaeger, OpenTelemetry
- **Security**: Dex, Istio (optional), cert-manager
- **Cost Management**: OpenCost

## 🛡️ Security

KOF implements multiple security layers:

- **Authentication**: Dex SSO with multiple identity providers
- **Authorization**: Kubernetes RBAC with least-privilege access
- **Transport Security**: TLS/mTLS for all communications
- **Network Security**: Istio service mesh (optional) with strict mTLS
- **Container Security**: Non-root containers, security contexts, minimal images

See [SECURITY.md](docs/SECURITY.md) for detailed security configuration.

## 📊 Monitoring & Alerting

KOF provides comprehensive monitoring out of the box:

- **Infrastructure Metrics**: CPU, memory, storage, network
- **Application Metrics**: Custom metrics via Prometheus
- **Log Aggregation**: Centralized logging with search and alerting
- **Distributed Tracing**: End-to-end request tracing
- **Cost Tracking**: Resource usage and cost optimization

## 🤝 Contributing

We welcome contributions! Please see our [Contribution Guidelines](CONTRIBUTING.md).

### Development Requirements

- Go 1.24+
- Node.js 18.18.2+
- Docker 17.03+
- kubectl 1.11.3+
- Kubernetes cluster access

### Conventional Commits

We follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) specification for all commit messages.

## 📈 Production Deployments

KOF is designed for production use with:

- **High Availability**: Multi-replica deployments with leader election
- **Scalability**: Horizontal scaling support for all components
- **Monitoring**: Built-in health checks and metrics
- **Backup & Recovery**: Data persistence and backup strategies
- **Security**: Production-grade security configurations

## 📦 Releases

- **Stable Releases**: See [GitHub Releases](https://github.com/k0rdent/kof/releases)
- **Container Images**: Available at `ghcr.io/k0rdent/kof`
- **Helm Charts**: Published to `oci://ghcr.io/k0rdent/kof/charts`

## 📞 Support

- **Documentation**: [docs.k0rdent.io](https://docs.k0rdent.io/next/admin/kof/)
- **Issues**: [GitHub Issues](https://github.com/k0rdent/kof/issues)
- **Discussions**: [GitHub Discussions](https://github.com/k0rdent/kof/discussions)

## 📄 License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.

---

**Built with ❤️ by the k0rdent team**

#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Prerequisites Setup Script
# Installs: Docker, kubectl, kind, Helm, ArgoCD CLI
# Supports: macOS (Homebrew) and Linux (Ubuntu/Debian via WSL2 or native)
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

OS="$(uname -s)"

check_command() {
    if command -v "$1" &> /dev/null; then
        info "$1 is already installed: $(command -v "$1")"
        return 0
    fi
    return 1
}

# --- Docker ---
install_docker() {
    if check_command docker; then return; fi

    if [[ "$OS" == "Darwin" ]]; then
        warn "Docker Desktop must be installed manually on macOS."
        warn "Download from: https://www.docker.com/products/docker-desktop/"
        warn "After installing, ensure Docker Desktop is running."
    else
        info "Installing Docker via apt..."
        sudo apt-get update
        sudo apt-get install -y ca-certificates curl gnupg
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
        sudo usermod -aG docker "$USER"
        warn "You may need to log out and back in for Docker group permissions to take effect."
    fi
}

# --- kubectl ---
install_kubectl() {
    if check_command kubectl; then return; fi

    if [[ "$OS" == "Darwin" ]]; then
        info "Installing kubectl via Homebrew..."
        brew install kubectl
    else
        info "Installing kubectl..."
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
    fi
}

# --- kind ---
install_kind() {
    if check_command kind; then return; fi

    if [[ "$OS" == "Darwin" ]]; then
        info "Installing kind via Homebrew..."
        brew install kind
    else
        info "Installing kind..."
        KIND_VERSION=$(curl -s https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
        curl -Lo kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
        sudo install -o root -g root -m 0755 kind /usr/local/bin/kind
        rm kind
    fi
}

# --- Helm ---
install_helm() {
    if check_command helm; then return; fi

    if [[ "$OS" == "Darwin" ]]; then
        info "Installing Helm via Homebrew..."
        brew install helm
    else
        info "Installing Helm..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
}

# --- ArgoCD CLI ---
install_argocd_cli() {
    if check_command argocd; then return; fi

    if [[ "$OS" == "Darwin" ]]; then
        info "Installing ArgoCD CLI via Homebrew..."
        brew install argocd
    else
        info "Installing ArgoCD CLI..."
        ARGOCD_VERSION=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
        curl -sSL -o argocd "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
        sudo install -o root -g root -m 0755 argocd /usr/local/bin/argocd
        rm argocd
    fi
}

# --- Main ---
echo ""
echo "========================================="
echo "  CI/CD Pipeline - Prerequisites Setup"
echo "========================================="
echo ""
info "Detected OS: $OS"
echo ""

install_docker
install_kubectl
install_kind
install_helm
install_argocd_cli

echo ""
echo "========================================="
info "Prerequisites installation complete!"
echo "========================================="
echo ""
info "Verify installations:"
echo "  docker --version"
echo "  kubectl version --client"
echo "  kind --version"
echo "  helm version"
echo "  argocd version --client"
echo ""

#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Prerequisites Setup Script
#
# Installs: Docker, kubectl, kind, Helm, ArgoCD CLI
#
# Supported platforms:
#   - macOS (requires Homebrew)
#   - Linux: Ubuntu/Debian (including WSL2)
#
# This script is IDEMPOTENT - safe to run multiple times. Existing tools
# are detected and installation is skipped for anything already present.
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step()  { echo -e "\n${BLUE}==>${NC} $1"; }

OS="$(uname -s)"

has_command() {
    command -v "$1" &> /dev/null
}

# --- Platform checks ---

check_platform() {
    step "Detecting platform"
    info "OS: $OS"

    if [[ "$OS" == "Darwin" ]]; then
        if ! has_command brew; then
            error "Homebrew is required on macOS but was not found.
           Install from https://brew.sh and re-run this script."
        fi
        info "Homebrew detected: $(brew --version | head -n 1)"
    elif [[ "$OS" == "Linux" ]]; then
        if ! has_command apt-get; then
            error "This script supports Ubuntu/Debian Linux only.
           For other distros, please install the tools manually."
        fi
        info "Debian-family Linux detected"
    else
        error "Unsupported OS: $OS (only macOS and Linux are supported)"
    fi
}

# --- Docker ---

install_docker() {
    step "Docker"
    if has_command docker; then
        info "Docker already installed: $(docker --version)"
        return
    fi

    if [[ "$OS" == "Darwin" ]]; then
        warn "Docker Desktop must be installed manually on macOS."
        warn "Download: https://www.docker.com/products/docker-desktop/"
        warn "After installing, ensure Docker Desktop is running, then re-run this script."
        error "Install Docker Desktop and re-run this script."
    fi

    # Linux path (Ubuntu/Debian). In WSL2, Docker is typically provided by
    # Docker Desktop for Windows with WSL integration - if that's set up,
    # 'docker' is already on PATH and we never reach here.
    info "Installing Docker via apt..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq ca-certificates curl gnupg

    # Idempotent: install -d creates only if missing
    sudo install -m 0755 -d /etc/apt/keyrings

    # Idempotent: only import GPG key if missing
    if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
            | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
    fi

    # Idempotent: only write sources list if missing
    if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
          https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
          | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi

    sudo apt-get update -qq
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Idempotent: skip group add if already a member
    if ! groups "$USER" | grep -q '\bdocker\b'; then
        sudo usermod -aG docker "$USER"
        warn "Added $USER to the docker group. Log out and back in for this to take effect."
    fi
}

# --- kubectl ---

install_kubectl() {
    step "kubectl"
    if has_command kubectl; then
        info "kubectl already installed: $(kubectl version --client 2>&1 | head -n 1)"
        return
    fi

    if [[ "$OS" == "Darwin" ]]; then
        info "Installing kubectl via Homebrew..."
        brew install kubectl
    else
        info "Installing kubectl..."
        local stable_version
        stable_version=$(curl -L -s https://dl.k8s.io/release/stable.txt)
        curl -LO "https://dl.k8s.io/release/${stable_version}/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm -f kubectl
    fi
}

# --- kind ---

install_kind() {
    step "kind"
    if has_command kind; then
        info "kind already installed: $(kind --version)"
        return
    fi

    if [[ "$OS" == "Darwin" ]]; then
        info "Installing kind via Homebrew..."
        brew install kind
    else
        info "Installing kind..."
        local kind_version
        kind_version=$(curl -s https://api.github.com/repos/kubernetes-sigs/kind/releases/latest \
            | grep '"tag_name"' | cut -d'"' -f4)
        curl -Lo kind "https://kind.sigs.k8s.io/dl/${kind_version}/kind-linux-amd64"
        sudo install -o root -g root -m 0755 kind /usr/local/bin/kind
        rm -f kind
    fi
}

# --- Helm ---

install_helm() {
    step "Helm"
    if has_command helm; then
        info "Helm already installed: $(helm version --short)"
        return
    fi

    if [[ "$OS" == "Darwin" ]]; then
        info "Installing Helm via Homebrew..."
        brew install helm
    else
        info "Installing Helm via official script..."
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
}

# --- ArgoCD CLI ---

install_argocd_cli() {
    step "ArgoCD CLI"
    if has_command argocd; then
        info "ArgoCD CLI already installed: $(argocd version --client 2>&1 | head -n 1)"
        return
    fi

    if [[ "$OS" == "Darwin" ]]; then
        info "Installing ArgoCD CLI via Homebrew..."
        brew install argocd
    else
        info "Installing ArgoCD CLI..."
        local argocd_version
        argocd_version=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest \
            | grep '"tag_name"' | cut -d'"' -f4)
        curl -sSL -o argocd "https://github.com/argoproj/argo-cd/releases/download/${argocd_version}/argocd-linux-amd64"
        sudo install -o root -g root -m 0755 argocd /usr/local/bin/argocd
        rm -f argocd
    fi
}

# --- Verification ---

verify_installation() {
    step "Verifying installations"

    local failed=0
    local tools=("docker" "kubectl" "kind" "helm" "argocd")

    for tool in "${tools[@]}"; do
        if has_command "$tool"; then
            info "[OK]   $tool  ->  $(command -v "$tool")"
        else
            warn "[FAIL] $tool  NOT FOUND"
            failed=$((failed + 1))
        fi
    done

    echo ""
    if [[ $failed -gt 0 ]]; then
        error "$failed tool(s) failed to install. See errors above."
    fi

    info "All 5 tools are installed and on PATH."
}

# --- Main ---

main() {
    echo ""
    echo "========================================="
    echo "  Prerequisites Setup (idempotent)"
    echo "========================================="

    check_platform
    install_docker
    install_kubectl
    install_kind
    install_helm
    install_argocd_cli
    verify_installation

    echo ""
    echo "========================================="
    info "Setup complete. You're ready to deploy."
    echo "========================================="
    echo ""
}

main "$@"
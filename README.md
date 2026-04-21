# Hello World CI/CD Pipeline

A containerized Flask web app deployed to Kubernetes via a GitHub Actions
CI pipeline and ArgoCD GitOps, built for the Jamf Systems Development
Engineer take-home assignment.

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│  Developer                                                         │
│      │                                                             │
│      │ git push main                                               │
│      ▼                                                             │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  GitHub Actions CI                                           │  │
│  │    ├─ pytest (Flask app tests)                               │  │
│  │    ├─ helm lint + helm template (chart validation)           │  │
│  │    └─ docker buildx build --push (multi-arch image)          │  │
│  └──────────────────────────────────────────────────────────────┘  │
│      │                                                             │
│      │ publish image                                               │
│      ▼                                                             │
│  ghcr.io/<user>/hello-world-cicd:{latest, <sha>}   (public)        │
│                                                                    │
│      ▲                                                             │
│      │ pull image                                                  │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Kubernetes cluster (kind)                                   │  │
│  │                                                              │  │
│  │   argocd namespace          staging namespace                │  │
│  │   ┌──────────────┐          ┌──────────────────┐             │  │
│  │   │   ArgoCD     │──deploy─▶│  hello-world     │             │  │
│  │   │              │          │  (1 replica)     │             │  │
│  │   │  watches Git │          │  tag: latest     │             │  │
│  │   └──────────────┘          └──────────────────┘             │  │
│  │          │                                                   │  │
│  │          │                  prod namespace                   │  │
│  │          │                  ┌──────────────────┐             │  │
│  │          └──────deploy─────▶│  hello-world     │             │  │
│  │                             │  (3 replicas)    │             │  │
│  │                             │  tag: <sha>      │             │  │
│  │                             └──────────────────┘             │  │
│  └──────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────┘
```


## Prerequisites

You'll need the following installed locally:

- **Docker** 24+ ([install](https://docs.docker.com/get-docker/))
- **kubectl** 1.28+ ([install](https://kubernetes.io/docs/tasks/tools/))
- **kind** 0.20+ ([install](https://kind.sigs.k8s.io/docs/user/quick-start/#installation))
- **Helm** 3.12+ ([install](https://helm.sh/docs/intro/install/))
- **Git** (any recent version)

All tools are available on macOS via Homebrew and Linux via the official install methods linked above.

**Convenience script:** [`scripts/setup-prerequisites.sh`](scripts/setup-prerequisites.sh) installs all of the above on macOS (Homebrew) or Ubuntu/Debian (apt). Idempotent — safe to re-run. Skip if you already have these tools installed.


## Quick Start

From a clean state, the following commands will deploy the app end-to-end:

```bash
# 1. Clone the repo
git clone https://github.com/wrenywren/hello-world-cicd.git
cd hello-world-cicd

# 2. Create a local Kubernetes cluster
kind create cluster --name hello-world

# 3. Install ArgoCD into the cluster
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 4. Wait for ArgoCD server to be ready (~60-90 seconds)
kubectl wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd --timeout=300s

# 5. Deploy both environments via ArgoCD
kubectl apply -f argocd/application-staging.yaml
kubectl apply -f argocd/application-prod.yaml

# 6. Check deployment status (ArgoCD takes another 60-90 seconds to sync)
kubectl get applications -n argocd
kubectl get pods -n staging
kubectl get pods -n prod
```

Both Applications should show `Synced` and `Healthy`. You'll see one pod in `staging` and three in `prod`.

### Access the ArgoCD UI

```bash
# In a separate terminal, port-forward the ArgoCD server
kubectl port-forward svc/argocd-server -n argocd 8443:443

# Retrieve the admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

Open **https://localhost:8443** in your browser, accept the self-signed cert warning, and log in with:
- Username: `admin`
- Password: (from the command above)

### Access the Flask app

```bash
# Staging (1 replica)
kubectl port-forward -n staging svc/hello-world 8080:80
# Browser: http://localhost:8080
# Or: curl -w "\n" http://localhost:8080

# Production (3 replicas) — in a separate terminal
kubectl port-forward -n prod svc/hello-world 8081:80
# Browser: http://localhost:8081
# Or: curl -w "\n" http://localhost:8081
```

### Clean up

```bash
kind delete cluster --name hello-world
```


## Project Structure

```
hello-world-cicd/
├── app/                             # Flask application
│   ├── app.py                       # Hello World + /health endpoints
│   ├── requirements.txt             # Python dependencies
│   ├── pytest.ini                   # Test runner config
│   └── tests/                       # Unit tests
├── argocd/                          # GitOps Application manifests
│   ├── application-staging.yaml     # Deploys to `staging` namespace
│   └── application-prod.yaml        # Deploys to `prod` namespace
├── helm/
│   └── hello-world/                 # Helm chart for the Flask app
│       ├── Chart.yaml               # Chart metadata
│       ├── values.yaml              # Base values (defaults)
│       ├── values-staging.yaml      # Staging overrides
│       ├── values-prod.yaml         # Production overrides
│       └── templates/
│           ├── deployment.yaml      # Kubernetes Deployment
│           ├── service.yaml         # Kubernetes Service
│           ├── _helpers.tpl         # Named template helpers
│           └── NOTES.txt            # Post-install instructions
├── scripts/
│   └── setup-prerequisites.sh       # Optional convenience installer
├── .github/
│   └── workflows/
│       └── ci.yaml                  # GitHub Actions CI pipeline
├── Dockerfile                       # Multi-stage build, non-root, gunicorn
└── README.md                        # You are here
```


## How It Works

### CI Pipeline (GitHub Actions)

On every push to `main`, `.github/workflows/ci.yaml` runs three jobs in parallel:

- **Test** — runs pytest against the Flask app
- **Validate** — runs `helm lint` and `helm template` on the chart
- **Build and Push** — builds a multi-arch Docker image and pushes it to `ghcr.io`, tagged with both the short git SHA and `latest`

The build-and-push job only runs if both other jobs pass, and only on pushes to `main` (not on pull requests). Images are built with Buildx and use GitHub Actions cache to speed up successive runs.

### Helm Chart

`helm/hello-world/` defines the Kubernetes deployment. The chart produces two resources: a `Deployment` (the pod spec) and a `Service` (stable network access via ClusterIP).

Values are layered via Helm's default merge behavior. `values.yaml` contains the base defaults — replica count, image repo, resource limits, security context, liveness/readiness probes. Environment overrides (`values-staging.yaml` and `values-prod.yaml`) sit on top to change replica counts, image tags, and resource sizing per environment.

### GitOps with ArgoCD

ArgoCD runs inside the cluster in its own namespace (`argocd`). Two `Application` resources — one for staging, one for production — tell ArgoCD which repo to watch, which Helm chart to render, which values files to merge, and which target namespace to deploy into.

Both Applications use automated sync with `prune: true` and `selfHeal: true`. Any drift from Git (manual `kubectl edit`, a deleted resource, etc.) gets reverted within a sync interval. Git is the single source of truth.

### Multi-Environment Strategy

Both environments deploy the same chart from the same repo — they differ only in which values file layers on top and which namespace they target.

| | Staging | Production |
|--|--|--|
| Namespace | `staging` | `prod` |
| Replicas | 1 | 3 |
| Image tag | `:latest` | Pinned SHA |
| Pull policy | `Always` | `IfNotPresent` |

The image tag strategy is intentional: staging tracks `latest` for fast iteration, production pins to a specific SHA so ArgoCD can detect image changes as Git diffs. See [Design Decisions](#design-decisions) for the reasoning.


## Design Decisions

| Decision | Choice | Why |
|---|---|---|
| App language | Python/Flask | Familiarity + tiny app, language doesn't matter |
| Local cluster | kind | Faster + lighter than minikube VM |
| Image registry | ghcr.io | Native GitHub auth, simple public access |
| Container user | Non-root (UID 1000) | Running as root inside a container is a common self-infliected security flaw ; running as an unprivileged user closes it |
| WSGI server | gunicorn | Flask dev server is single-threaded + warns loudly |
| GitOps tool | ArgoCD | Jamf's Nexus team uses it, matches requirements |
| Staging image tag | `:latest` + pull always | Fast iteration |
| Production image tag | Pinned SHA + pull if-not-present | GitOps auditability |
| Chart scope | Deployment + Service only | Removed unused scaffolding (SA, Ingress, HPA, etc.) |

### Image tag strategy (most important tradeoff)

Worth the most discussion: ArgoCD detects changes by diffing Git state against cluster state. A floating tag like `:latest` doesn't change string values between builds — ArgoCD can't distinguish "new latest" from "old latest" and auditability breaks.

Pinning production to an immutable SHA means every production deploy corresponds to an explicit commit changing the tag in `values-prod.yaml`. Clean Git history of what was deployed when. Slower workflow, but worth it for anything that bears production traffic.

### Chart simplification

`helm create` ships with scaffolding for ServiceAccount, Ingress, HPA, HTTPRoute, and more. Stripped it to Deployment + Service + helpers because:

- App doesn't call the K8s API → dedicated ServiceAccount adds nothing
- No ingress controller in kind → port-forward is simpler  
- No metrics-server in kind → HPA non-functional anyway

Dead config is technical debt.


## Security Notes

### What's in place today

| Layer | Control |
|---|---|
| Image | Multi-stage build keeps the final image small and reduces attack surface |
| Image | Runs as unprivileged user (`appuser`, UID 1000) |
| Pod | `runAsNonRoot: true`, `allowPrivilegeEscalation: false` |
| Pod | All Linux capabilities dropped (`capabilities.drop: [ALL]`) |
| Network | Service is `ClusterIP` only — no external exposure |
| Supply chain | Image hosted on GitHub Container Registry, built from known-good Dockerfile |
| GitOps | Automated drift detection — manual `kubectl` changes get reverted |

### What I'd add for a production deployment

**Image hardening**

- Image scanning in CI (Trivy or Snyk) — fail the build on critical CVEs
- Signed images with Cosign, verified at admission time
- SBOM generation and storage for supply-chain auditing
- Switch base image to `python:3.12-slim` variant with additional distroless considerations for the runtime stage

**Kubernetes hardening**

- Dedicated ServiceAccount with explicit RBAC scoped to only what the pod actually needs (currently nothing — but defense-in-depth)
- NetworkPolicies limiting ingress/egress to the pod (deny-all default, allow only required flows)
- Pod Security Standards enforced at the namespace level (`restricted` profile)
- Read-only root filesystem (`readOnlyRootFilesystem: true`) with writable `emptyDir` volumes where needed

**Secrets and runtime**

- Integration with a secrets manager (Vault, External Secrets Operator, or cloud-native like AWS Secrets Manager / Azure Key Vault)
- Workload Identity for pods needing cloud API access, not static credentials

**Supply chain and GitOps**

- Private GitHub repo with branch protection requiring PR reviews for `values-prod.yaml` changes
- ArgoCD with SSO (not `admin/initial-admin-secret`) and RBAC limiting who can sync which Applications
- Real TLS certs for the ArgoCD UI and the app's ingress, managed via cert-manager with Let's Encrypt or an internal CA
- Secrets in ArgoCD-managed charts via sealed-secrets, SOPS, or the External Secrets Operator — never committed plaintext in values files
- Separate ArgoCD instance per tier, or cluster-scoped RBAC isolating staging and prod operators
- Admission controllers (OPA/Gatekeeper or Kyverno) enforcing policy at deploy time, for example blocking `:latest` tags in the prod namespace

### Notes on this environment

A few controls are deliberately simplified for demo reproducibility:

- Image is **public** on ghcr.io so judges can pull without auth. In production, images would live in a private registry with pull secrets or workload identity.
- ArgoCD uses the **default admin credentials** and a self-signed cert. Production installs integrate with SSO (Okta, Azure AD, etc.) and use real TLS.
- There is **no secret material** in the app, so no secrets management is wired in. A real app would use one of the patterns above from day one.


## Known Issues

### `argocd-applicationset-controller` crashloops on install

After `kubectl apply`ing the ArgoCD install manifest, the `argocd-applicationset-controller` pod enters `CrashLoopBackOff` due to a large annotation on the `applicationsets.argoproj.io` CRD exceeding kubectl's client-side apply size limit.

**Impact:** None for this project — ApplicationSets are used to programmatically generate multiple Applications from a template. This project uses two hand-authored `Application` resources, so the ApplicationSet controller is not on the critical path.

**Workaround:** `kubectl apply --server-side` resolves the CRD install but introduces transient connectivity issues between the `argocd-server` and `argocd-repo-server` during initial sync. Standard `kubectl apply` was chosen for reliable reproduction at the cost of one cosmetic crashloop.

**Production fix:** Install ArgoCD via the official Helm chart or the Argo CD Operator rather than the raw manifest used here. Both handle CRD installation cleanly.


## What I'd Do With More Time

Scope was constrained to ~10 hours per the assignment. Security improvements are covered above in [Security Notes](#security-notes). Beyond those, the gaps I'd close for a production-bound version:

**Chart**

- Ingress or HTTPRoute for real external access instead of `kubectl port-forward`
- Pod Disruption Budget to keep at least N replicas during node drains
- Helm chart tests (`helm test`) that verify the deployed Service actually responds

**CI/CD**

- Promote-to-production workflow that opens a PR updating `image.tag` in `values-prod.yaml`
- GitHub environment protection rules on the production deployment
- Separate workflow for release tagging (semver on main, not just git SHA)

**GitOps**

- ApplicationSet replacing the two hand-authored Application manifests (template + list generator for environments)
- Automated rollback on health check failure post-sync

**Observability**

- Prometheus metrics endpoint on the Flask app (`/metrics`)
- ServiceMonitor resource for scraping
- Grafana dashboard as a sibling chart
- Structured JSON logging instead of gunicorn's default

**Testing**

- Integration tests running against a kind cluster in CI
- Smoke test job post-deploy that hits both environments' services

None of these are novel — they're the standard next layer for anything bearing real traffic.


## Resources

References I consulted while building this:

- [ArgoCD Getting Started](https://argo-cd.readthedocs.io/en/stable/getting_started/) for the install and first-Application walkthrough
- [Helm documentation](https://helm.sh/docs/) for chart structure and template syntax
- [kind Quick Start](https://kind.sigs.k8s.io/docs/user/quick-start/) for local cluster setup
- [GitHub Container Registry docs](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry) for ghcr.io publishing from GitHub Actions
- [docker/metadata-action](https://github.com/docker/metadata-action) for the multi-tag image publishing pattern
- [Kubernetes recommended labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/) reference for the standard `app.kubernetes.io/*` label set

AI assistance (Claude) was used for sanity-checking Helm template syntax, reviewing the Dockerfile for security defaults, and drafting portions of this README. Every design decision and line of code was reviewed and validated against the official documentation linked above.
# k8s-aws-observability-demo

A small, end-to-end DevOps project: a Python service is containerized, deployed to Kubernetes, monitored with Prometheus and Grafana, and shipped to AWS EKS through infrastructure defined in Terraform and a GitHub Actions pipeline.

The service itself is deliberately trivial. The point is the platform around it.

## What it shows

| Area | What is implemented |
|---|---|
| **Application** | FastAPI service exposing Prometheus metrics (request rate, errors, latency histogram), liveness/readiness probes, a CPU-bound endpoint for autoscaling, and failure injection for alert demos |
| **Containers** | Multi-stage Docker build, slim runtime image, non-root user |
| **Kubernetes** | Kustomize base + `local` / `aws` overlays; Deployment with zero-downtime rolling updates, probes, resource limits, hardened security context; Service, HPA, PodDisruptionBudget, ConfigMap |
| **Observability** | kube-prometheus-stack (Prometheus, Grafana, Alertmanager), ServiceMonitor, alert rules (service down, error rate > 5%, p95 latency > 500 ms), Grafana dashboard provisioned as code |
| **Infrastructure as Code** | Terraform: VPC across 2 AZs, EKS with a managed node group, ECR with scan-on-push and lifecycle policy, GitHub OIDC role (no static AWS keys), optional S3 remote state |
| **CI/CD** | GitHub Actions: lint + tests with coverage gate, image build + Trivy vulnerability scan, manifest validation with kubeconform, `terraform fmt/validate` + tflint, end-to-end deploy to a kind cluster with smoke tests; manual deploy workflow to EKS |

## Architecture

```text
 GitHub ──push──▶ CI: test → build → scan → validate → deploy to kind → smoke test
    │
    └─manual──▶ Deploy: OIDC → AWS ──▶ push image to ECR ──▶ kubectl apply -k (EKS)

 ┌──────────────── AWS (Terraform) ────────────────┐
 │ VPC: public subnets (NLB) / private subnets     │
 │   EKS cluster ── managed node group (t3.medium) │
 │     namespace status-api: Deployment, HPA, Svc  │
 │     namespace monitoring: Prometheus, Grafana   │
 │ ECR repository · IAM role for GitHub Actions    │
 └─────────────────────────────────────────────────┘

 Prometheus ──scrapes /metrics (ServiceMonitor)──▶ status-api pods
     │──evaluates alert rules──▶ Alertmanager
     └──datasource──▶ Grafana dashboard "status-api"
```

## Repository layout

```text
app/                    FastAPI service, tests, Dockerfile
k8s/base/               Deployment, Service, HPA, PDB, ConfigMap, ServiceMonitor, PrometheusRule
k8s/overlays/local/     kind: locally built image
k8s/overlays/aws/       EKS: ECR image, NLB service
k8s/kind-config.yaml    3-node local cluster
monitoring/             kube-prometheus-stack values + Grafana dashboard
infra/terraform/        VPC, EKS, ECR, GitHub OIDC
.github/workflows/      ci.yml, deploy.yml
scripts/load.sh         load generator for the HPA demo
Makefile                every command in one place (`make help`)
```

## Quick start: local cluster (free)

Requirements: Docker, [kind](https://kind.sigs.k8s.io/), kubectl, Helm, Python 3.11+, make.

```bash
make venv test          # unit tests
make up                 # kind cluster + metrics-server + monitoring + app (~5 min)
make port-forward       # terminal 1: API on http://localhost:8080
make grafana            # terminal 2: Grafana on http://localhost:3000 (admin / admin)
```

Then try the demo scenarios:

```bash
# Autoscaling: watch replicas grow from 2 to up to 5
kubectl -n status-api get hpa,pods -w   # terminal 3
make load                                # terminal 4

# Alerting: 20% of requests start failing; StatusApiHighErrorRate fires after ~5 min of traffic
make fail-on
make load
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090  # see Alerts tab
make fail-off
```

Open the **status-api** dashboard in Grafana to see rate, errors, latency, CPU and memory per pod.

Clean up: `make kind-down`.

## Deploy to AWS

> **Costs money while running** (EKS control plane, NAT gateway, two EC2 nodes — roughly $6–7 per day in eu-central-1). Run `make tf-destroy` when done.

1. Configure AWS credentials locally (`aws configure` or SSO) with permissions to create VPC, EKS, ECR and IAM resources.
2. Create the infrastructure:

   ```bash
   cp infra/terraform/terraform.tfvars.example infra/terraform/terraform.tfvars   # set github_repository
   make tf-init tf-plan tf-apply
   ```

3. Connect kubectl and install cluster add-ons:

   ```bash
   $(terraform -chdir=infra/terraform output -raw configure_kubectl)
   helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system --repo https://kubernetes-sigs.github.io/metrics-server/
   make monitoring
   ```

4. In the GitHub repository settings add the secret `AWS_ROLE_ARN` (from `terraform output github_actions_role_arn`) and the variables `AWS_REGION`, `EKS_CLUSTER_NAME`, `ECR_REPOSITORY`.
5. Run the **Deploy to EKS** workflow from the Actions tab. It prints the load balancer hostname at the end.
6. Tear down: `kubectl delete -k k8s/overlays/aws` (removes the load balancer first), then `make tf-destroy`.

## Design decisions

- **Kustomize over Helm for the app** — plain manifests with small per-environment patches; Helm is used where it shines, for third-party stacks (monitoring, metrics-server).
- **Route templates as metric labels** — `/api/work`, never raw URLs, to keep Prometheus label cardinality bounded.
- **OIDC instead of access keys** — CI receives short-lived credentials, and only workflows on `main` of this repository can assume the role.
- **Immutable image tags** — every deploy is the git SHA, so a rollback is just redeploying an older SHA (`kubectl rollout undo` also works).
- **Zero-downtime rollouts** — `maxUnavailable: 0`, readiness probes and a PodDisruptionBudget.

## Simplifications (what production would add)

Single NAT gateway, a public EKS API endpoint, a cluster-admin access entry for CI, and an NLB without TLS keep the demo short. A production setup would add private endpoint access or CIDR allow-lists, a namespace-scoped deploy role, Ingress with cert-manager/ACM for TLS, Alertmanager receivers (Slack/PagerDuty), persistent storage for Prometheus, and a GitOps controller such as Argo CD.

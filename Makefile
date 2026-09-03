CLUSTER   ?= status-api
IMAGE     ?= status-api:local
TF_DIR    := infra/terraform
VENV      := app/.venv
PY        := $(VENV)/bin

.DEFAULT_GOAL := help
.PHONY: help venv lint test run docker-build \
        kind-up kind-load metrics-server monitoring deploy-local up port-forward grafana load fail-on fail-off kind-down \
        validate tf-init tf-plan tf-apply tf-destroy

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# ---------- App ----------
venv: ## Create virtualenv and install the app with dev tools
	python3 -m venv $(VENV)
	$(PY)/pip install -e 'app[dev]'

lint: ## Ruff lint and format check
	cd app && ../$(PY)/ruff check . && ../$(PY)/ruff format --check .

test: ## Run unit tests with coverage
	cd app && ../$(PY)/pytest --cov=status_api --cov-report=term-missing

run: ## Run the API locally on :8000
	cd app && ../$(PY)/uvicorn status_api.main:app --reload

docker-build: ## Build the container image
	docker build --tag $(IMAGE) app

# ---------- Local Kubernetes (kind) ----------
kind-up: ## Create a 3-node kind cluster
	kind create cluster --config k8s/kind-config.yaml

kind-load: docker-build ## Build the image and load it into kind
	kind load docker-image $(IMAGE) --name $(CLUSTER)

metrics-server: ## Install metrics-server (needed by the HPA)
	helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ --force-update
	helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system \
	  --set 'args={--kubelet-insecure-tls}' --wait

monitoring: ## Install Prometheus + Grafana + Alertmanager and the dashboard
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
	helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
	  -n monitoring --create-namespace -f monitoring/values.yaml --wait --timeout 10m
	kubectl apply -k monitoring

deploy-local: kind-load ## Deploy the app to kind
	kubectl apply -k k8s/overlays/local
	kubectl -n status-api rollout status deployment/status-api --timeout=120s

up: kind-up metrics-server monitoring deploy-local ## Everything from scratch: cluster, monitoring, app
	@echo "Done. Run 'make port-forward' and 'make grafana' in separate terminals."

port-forward: ## Expose the API on http://localhost:8080
	kubectl -n status-api port-forward svc/status-api 8080:80

grafana: ## Expose Grafana on http://localhost:3000 (admin / admin)
	kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80

load: ## Generate CPU load for ~2 minutes to watch the HPA scale out
	./scripts/load.sh http://localhost:8080 120

fail-on: ## Make 20% of requests fail to trigger the error-rate alert
	kubectl -n status-api set env deployment/status-api FAILURE_RATE=0.2

fail-off: ## Stop injecting failures
	kubectl -n status-api set env deployment/status-api FAILURE_RATE=0

kind-down: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER)

validate: ## Render all manifests (the same check CI runs with kubeconform)
	kubectl kustomize k8s/overlays/local > /dev/null
	kubectl kustomize k8s/overlays/aws > /dev/null
	kubectl kustomize monitoring > /dev/null
	@echo "Manifests render OK"

# ---------- AWS (Terraform) ----------
tf-init: ## terraform init
	terraform -chdir=$(TF_DIR) init

tf-plan: ## terraform plan
	terraform -chdir=$(TF_DIR) plan

tf-apply: ## Create VPC, EKS, ECR, OIDC role (costs money while running!)
	terraform -chdir=$(TF_DIR) apply

tf-destroy: ## Destroy everything created by Terraform
	terraform -chdir=$(TF_DIR) destroy

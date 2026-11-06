SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

CLUSTER      ?= platform-lab
TF_DIR       := infra/terraform/kind
KUBECONFIG   ?= $(HOME)/.kube/platform-lab
STATE_DIR    ?= $(HOME)/.config/platform-lab
API_DIR      := apps/api
IMAGE        ?= ghcr.io/esleyms/platform-lab-api
export KUBECONFIG STATE_DIR

##@ Ciclo de vida

.PHONY: up
up: preflight cluster bootstrap ## Cria o cluster e entrega tudo ao Argo CD
	@scripts/wait-platform.sh
	@$(MAKE) --no-print-directory urls

.PHONY: down
down: ## Destroi o cluster (a chave do Sealed Secrets em $(STATE_DIR) é mantida)
	terraform -chdir=$(TF_DIR) destroy -auto-approve

.PHONY: cluster
cluster: ## Só o cluster kind via Terraform
	terraform -chdir=$(TF_DIR) init -input=false -upgrade >/dev/null
	terraform -chdir=$(TF_DIR) apply -auto-approve -input=false -var cluster_name=$(CLUSTER)

.PHONY: bootstrap
bootstrap: ## Segredos iniciais, Argo CD e a Application raiz
	@scripts/bootstrap.sh

.PHONY: preflight
preflight: ## Confere ferramentas, Docker e limites de inotify
	@scripts/preflight.sh

##@ Operação

.PHONY: status
status: ## Estado das Applications e dos pods com problema
	@kubectl -n argocd get applications.argoproj.io -o custom-columns='APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision'
	@echo
	@kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null || true

.PHONY: urls
urls: ## Endereços e credenciais do laboratório
	@echo "Argo CD  https://argocd.localhost   admin / $$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)"
	@echo "Grafana  https://grafana.localhost  admin / $$(cat $(STATE_DIR)/grafana-admin-password 2>/dev/null)"
	@echo "API dev  https://api-dev.localhost/api/items"
	@echo "API prod https://api.localhost/api/items"
	@echo "CA do laboratório: $(STATE_DIR)/ca.crt (make ca)"

.PHONY: ca
ca: ## Exporta a CA autoassinada para confiar no navegador/curl
	@mkdir -p $(STATE_DIR)
	@kubectl -n cert-manager get secret platform-lab-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > $(STATE_DIR)/ca.crt
	@echo "curl --cacert $(STATE_DIR)/ca.crt https://api-dev.localhost/readyz"

.PHONY: sync-prod
sync-prod: ## Dispara o sync manual de prod (equivale ao botão Sync do Argo CD)
	kubectl -n argocd patch applications.argoproj.io api-prod --type merge \
	  -p '{"operation":{"initiatedBy":{"username":"'"$$USER"'"},"sync":{"revision":"main","prune":true}}}'
	@echo "Acompanhe: kubectl -n argocd get application api-prod -w"

.PHONY: seal
seal: ## Gera o SealedSecret do token da API: make seal ENV=prod
	@scripts/seal-api-token.sh $(ENV)

.PHONY: load
load: ## Builda a imagem local e carrega no kind (sem passar pelo GHCR)
	docker build -t $(IMAGE):local --build-arg VERSION=local $(API_DIR)
	kind load docker-image $(IMAGE):local --name $(CLUSTER)

##@ Qualidade

.PHONY: test
test: ## Lint e testes da API
	cd $(API_DIR) && ruff check . && ruff format --check . && pytest

.PHONY: lint
lint: ## Lint de IaC, chart e manifestos (o mesmo do CI)
	terraform -chdir=$(TF_DIR) fmt -check -recursive
	helm lint charts/api -f gitops/envs/dev/values.yaml
	helm lint charts/api -f gitops/envs/prod/values.yaml
	yamllint -s .
	scripts/kubeconform.sh

.PHONY: help
help:
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2} /^##@/ {printf "\n%s\n", substr($$0, 5)}' $(MAKEFILE_LIST)

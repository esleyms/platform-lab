#!/usr/bin/env bash
# Provoca falhas em api-dev para treinar diagnóstico. Ver docs/troubleshooting-labs.md.
#   scripts/lab.sh <cenário>   aplica a falha
#   scripts/lab.sh reset       devolve o controle ao Argo CD (que desfaz tudo)
set -euo pipefail

NS=api-dev
DEPLOY=deploy/api

pause_gitops() {
  # A root recria a Application api-dev; por isso as duas perdem o sync automático.
  for app in root api-dev; do
    kubectl -n argocd patch applications.argoproj.io "$app" --type json \
      -p '[{"op":"remove","path":"/spec/syncPolicy/automated"}]' >/dev/null 2>&1 || true
  done
  echo "Sync automático de root e api-dev pausado. Ao terminar: scripts/lab.sh reset"
}

container_patch() {
  kubectl -n "$NS" patch "$DEPLOY" --type strategic -p \
    "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"api\",$1}]}}}}"
}

case "${1:-}" in
  image)
    pause_gitops
    kubectl -n "$NS" set image "$DEPLOY" api=ghcr.io/esleyms/platform-lab-api:nao-existe ;;
  probe)
    pause_gitops
    container_patch '"readinessProbe":{"httpGet":{"path":"/pronto","port":"http"}}' ;;
  crash)
    pause_gitops
    container_patch '"env":[{"name":"APP_DB_POOL_MAX","value":"muitos"}]' ;;
  oom)
    pause_gitops
    container_patch '"resources":{"limits":{"memory":"24Mi"},"requests":{"memory":"24Mi"}}' ;;
  quota)
    pause_gitops
    kubectl -n "$NS" patch hpa api --type merge -p '{"spec":{"minReplicas":3}}'
    container_patch '"resources":{"requests":{"cpu":"900m"}}' ;;
  netpol)
    pause_gitops
    kubectl -n "$NS" delete networkpolicy api ;;
  slo)
    pause_gitops
    container_patch '"env":[{"name":"APP_FAULT_ERROR_RATE","value":"0.3"}]'
    echo "Gere tráfego em outro terminal:"
    echo "  while true; do curl -sk -o /dev/null https://api-dev.localhost/api/items; sleep 0.2; done" ;;
  latency)
    pause_gitops
    container_patch '"env":[{"name":"APP_FAULT_LATENCY_MS","value":"450"}]' ;;
  reset)
    kubectl -n argocd patch applications.argoproj.io root --type merge \
      -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' >/dev/null
    echo "Root reativada; ela restaura api-dev do Git, e o self-heal desfaz as alterações manuais." ;;
  *)
    echo "uso: $0 {image|probe|crash|oom|quota|netpol|slo|latency|reset}"; exit 1 ;;
esac

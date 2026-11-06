#!/usr/bin/env bash
# Espera as Applications ficarem Healthy. prod tem sync manual, então fica fora da conta.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
timeout="${TIMEOUT:-900}"
deadline=$(( $(date +%s) + timeout ))
# root + uma Application por arquivo em gitops/apps
expected=$(( $(grep -rl '^kind: Application$' "$ROOT/gitops/apps" | wc -l) + 1 ))

while :; do
  apps=$(kubectl -n argocd get applications.argoproj.io \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.health.status}{"\n"}{end}')
  count=$(grep -c . <<<"$apps" || true)
  pending=$(awk '$1 != "api-prod" && $2 != "Healthy" {print $1"("$2")"}' <<<"$apps" | xargs)
  if (( count < expected )); then
    pending="${pending} [${count}/${expected} Applications criadas]"
  fi
  if [[ -z "${pending// /}" ]]; then
    echo "Plataforma pronta."
    exit 0
  fi
  if (( $(date +%s) > deadline )); then
    echo "Tempo esgotado. Ainda pendentes: $pending"
    echo "Diagnóstico: make status; kubectl -n argocd describe application <nome>"
    exit 1
  fi
  echo "Aguardando: $pending"
  sleep 15
done

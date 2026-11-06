#!/usr/bin/env bash
# Tudo que precisa existir ANTES do GitOps assumir: os "secret zero" e o próprio Argo CD.
# Daqui em diante, mudanças no cluster passam pelo Git.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="${STATE_DIR:-$HOME/.config/platform-lab}"
ARGOCD_CHART_VERSION="10.14.0"   # manter igual a gitops/apps/platform/argocd.yaml

mkdir -p "$STATE_DIR"
chmod 700 "$STATE_DIR"

ensure_ns() {
  kubectl create namespace "$1" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

# 1) Chave do Sealed Secrets trazida de fora do cluster.
#    Sem isso, cada `make down && make up` geraria uma chave nova e os SealedSecrets
#    commitados no Git deixariam de ser decifráveis.
if [[ ! -f "$STATE_DIR/sealed-secrets.key" ]]; then
  echo "Gerando par de chaves do Sealed Secrets em $STATE_DIR"
  openssl req -x509 -nodes -newkey rsa:4096 -days 3650 \
    -keyout "$STATE_DIR/sealed-secrets.key" -out "$STATE_DIR/sealed-secrets.crt" \
    -subj "/CN=sealed-secret/O=platform-lab" 2>/dev/null
  chmod 600 "$STATE_DIR/sealed-secrets.key"
fi
kubectl -n kube-system create secret tls platform-lab-sealing-key \
  --cert="$STATE_DIR/sealed-secrets.crt" --key="$STATE_DIR/sealed-secrets.key" \
  --dry-run=client -o yaml \
  | kubectl label --local -f - -o yaml sealedsecrets.bitnami.com/sealed-secrets-key=active \
  | kubectl apply -f - >/dev/null

# 2) Senha do Grafana gerada localmente (o chart usaria um valor fixo conhecido).
if [[ ! -f "$STATE_DIR/grafana-admin-password" ]]; then
  openssl rand -base64 24 | tr -d '\n' > "$STATE_DIR/grafana-admin-password"
  chmod 600 "$STATE_DIR/grafana-admin-password"
fi
ensure_ns monitoring
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-file=admin-password="$STATE_DIR/grafana-admin-password" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

# 3) Argo CD instalado uma vez pelo Helm; depois ele mesmo passa a se gerenciar
#    (gitops/apps/platform/argocd.yaml usa o mesmo chart e os mesmos values).
helm upgrade --install argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --version "$ARGOCD_CHART_VERSION" \
  --namespace argocd --create-namespace \
  --values "$ROOT/gitops/platform/argocd/values.yaml" \
  --wait --timeout 10m

# Namespaces que publicam rotas no Gateway compartilhado (ver gitops/platform/gateway/gateway.yaml).
kubectl label namespace argocd monitoring platform-lab/gateway-access=true --overwrite >/dev/null

# 4) A Application raiz: a partir daqui o estado desejado vem de gitops/apps.
kubectl apply -f "$ROOT/gitops/bootstrap/root.yaml"
echo "Argo CD instalado; sincronizando a plataforma a partir do Git."

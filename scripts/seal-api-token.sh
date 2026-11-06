#!/usr/bin/env bash
# Cria (ou rotaciona) o token de escrita da API como SealedSecret versionável.
# Uso: scripts/seal-api-token.sh prod   (depois: git add + commit + push)
set -euo pipefail

env="${1:?informe o ambiente: dev ou prod}"
[[ "$env" =~ ^(dev|prod)$ ]] || { echo "ambiente inválido: $env"; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="${STATE_DIR:-$HOME/.config/platform-lab}"
out="$ROOT/gitops/envs/$env/manifests/api-token.sealedsecret.yaml"
token="$(openssl rand -hex 32)"

# Cifra offline com o certificado público: não precisa de acesso ao cluster.
kubectl create secret generic api-token -n "api-$env" \
  --from-literal=token="$token" --dry-run=client -o yaml \
  | kubeseal --cert "$STATE_DIR/sealed-secrets.crt" --format yaml > "$out"

umask 077
echo -n "$token" > "$STATE_DIR/api-token-$env"
echo "Gerado $out"
echo "Token guardado em $STATE_DIR/api-token-$env (não vai para o Git)."
echo "Próximo passo: git add $out && git commit -m 'feat($env): token da API' && git push"

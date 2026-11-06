#!/usr/bin/env bash
# Valida o que o Argo CD vai aplicar: o chart renderizado por ambiente e os manifestos puros.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
K8S_VERSION="${K8S_VERSION:-master}"
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

for env in dev prod; do
  helm template api "$ROOT/charts/api" --namespace "api-$env" \
    -f "$ROOT/gitops/envs/$env/values.yaml" --set image.tag=ci > "$out/api-$env.yaml"
done
kubectl kustomize "$ROOT/gitops/platform/monitoring" > "$out/monitoring.yaml"

# Só arquivos que são manifestos: values.yaml de charts e kustomization ficam de fora.
mapfile -t manifests < <(find "$ROOT/gitops" -name '*.yaml' \
  ! -name values.yaml ! -name kustomization.yaml ! -path '*/platform/monitoring/*')

kubeconform -strict -summary \
  -kubernetes-version "$K8S_VERSION" \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  "$out"/*.yaml "${manifests[@]}"

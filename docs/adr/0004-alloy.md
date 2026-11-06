# ADR 0004: Grafana Alloy como coletor de logs

**Status:** aceita · **Data:** 2026-11

## Contexto

O Promtail, coletor tradicional do Loki, entrou em LTS em fevereiro de 2025 e chegou ao fim de vida em 2 de março de 2026. A Grafana direcionou o desenvolvimento para o Alloy.

## Decisão

Alloy com `loki.source.kubernetes`, lendo os logs pela API do Kubernetes, em um Deployment de uma réplica. Os logs JSON da API têm o campo `level` promovido a label.

## Consequências

- Não precisa de DaemonSet com `hostPath` em `/var/log`, o que reduz privilégios.
- Em clusters grandes, ler pela API sobrecarrega o kube-apiserver; o caminho seria DaemonSet com `loki.source.file` ou clustering do Alloy.
- Labels do Loki precisam de baixa cardinalidade: `namespace`, `app`, `container`, `level`. IDs de requisição e de item ficam no corpo do log, não em labels.

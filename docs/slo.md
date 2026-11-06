# SLOs da API

## SLIs

Contam apenas as rotas de negócio (`/api/*`). Probes e `/metrics` ficam de fora, porque não representam a experiência de quem usa a API.

| SLI | Definição | Fonte |
|---|---|---|
| Disponibilidade | requisições sem resposta 5xx ÷ total de requisições | `http_requests_total` |
| Latência | fração das requisições respondidas em até 300 ms | `http_request_duration_seconds` |

O rótulo `route` usa o template da rota (`/api/items/{item_id}`) e não o caminho real, para que cada ID não vire uma série nova no Prometheus.

## Objetivos

| SLO | Objetivo | Error budget |
|---|---|---|
| Disponibilidade | 99,5% | 0,5% das requisições |
| Latência | p95 < 300 ms | 5% das requisições acima de 300 ms |

Em 30 dias, 0,5% equivale a cerca de 3,6 horas de indisponibilidade total. No laboratório a retenção do Prometheus é de 3 dias, então o dashboard mostra o budget nessa janela; a lógica é a mesma.

## Alertas de disponibilidade: burn rate

Burn rate é a velocidade de consumo do budget. Burn rate 1 consome o budget exatamente no prazo do SLO; 14,4 consome 2% do budget mensal em uma hora.

| Alerta | Condição | Janelas | Severidade |
|---|---|---|---|
| `ApiErrorBudgetBurnFast` | erro > 14,4 × 0,5% = 7,2% | 1h **e** 5m | critical |
| `ApiErrorBudgetBurnSlow` | erro > 6 × 0,5% = 3% | 6h **e** 30m | warning |

Exigir as duas janelas é o que torna o alerta útil: a janela longa garante que o problema é relevante, a curta garante que ele ainda está acontecendo. Com só a janela de 1h, o alerta continuaria disparado por quase uma hora depois da correção. É a abordagem multi-janela e multi-burn-rate do capítulo 5 do *SRE Workbook* do Google.

## Alerta de latência

`ApiLatencyP95High` dispara quando o p95 de 5 minutos fica acima de 300 ms por 10 minutos. O p95 vem de `histogram_quantile` sobre os buckets do histograma, por isso há buckets em 0,2, 0,3 e 0,5 s: a precisão do quantil depende de existirem buckets perto do limite.

## Onde está no código

- Métricas: `apps/api/src/platform_api/observability.py`
- Regras de gravação e alertas: `charts/api/templates/prometheusrule.yaml`
- Dashboard: `gitops/platform/monitoring/dashboards/api-slo.json`
- Para ver os alertas disparando: `scripts/lab.sh slo` e `scripts/lab.sh latency`

# Runbook

Cada alerta da API aponta para uma seção deste arquivo pelo `runbook_url`.

Antes de qualquer coisa:

```bash
export KUBECONFIG=~/.kube/platform-lab
make status
kubectl -n <namespace> get pods,deploy,hpa
```

## ApiErrorBudgetBurnFast

**O que significa:** mais de 7,2% das requisições `/api/*` retornando 5xx, na última hora e nos últimos 5 minutos. No ritmo atual o budget acaba em cerca de dois dias.

**Diagnóstico**

1. Houve deploy recente? `kubectl -n <ns> rollout history deploy/api` e o histórico do Argo CD. Se a taxa de erro começou junto com uma nova revisão, essa é a principal suspeita.
2. Os erros vêm de todos os pods ou de um só? No Grafana, painel *Taxa de erro*, ou `sum by (pod) (rate(http_requests_total{namespace="<ns>",status=~"5.."}[5m]))`.
3. O banco está saudável? `kubectl -n <ns> get cluster api-db` e `kubectl -n <ns> get pods -l cnpg.io/cluster=api-db`.
4. Logs de erro: no Grafana Explore, `{namespace="<ns>", app="api", level="error"}`.

**Mitigação**

- Regressão de versão: reverter o commit da tag em `gitops/envs/<env>/values.yaml` e sincronizar. Não corrija para frente sob pressão se o rollback for possível.
- Falha injetada (`APP_FAULT_ERROR_RATE`): remover a variável.
- Banco: ver a seção de status do `Cluster` e os eventos do operator em `cnpg-system`.

## ApiErrorBudgetBurnSlow

**O que significa:** consumo contínuo de cerca de 6 vezes o sustentável nas últimas 6 horas. Não é urgente para agora, mas esgota o budget em uns 5 dias.

**Diagnóstico:** igual ao anterior, olhando para janelas maiores. Costuma ser uma rota específica falhando ou um pod problemático; agrupe por `route` e por `pod`.

**Ação:** abrir uma tarefa com prioridade. Se o budget do período acabar, a política é congelar mudanças que não sejam de confiabilidade até ele se recuperar.

## ApiLatencyP95High

**O que significa:** p95 acima de 300 ms por 10 minutos.

**Diagnóstico**

1. Saturação: `kubectl -n <ns> top pods` e o painel *CPU vs request*. Se o HPA está no máximo (`kubectl -n <ns> get hpa`), a capacidade acabou.
2. Throttling não deve ocorrer (a API não tem limit de CPU), mas confira se alguém adicionou: `kubectl -n <ns> get deploy api -o jsonpath='{.spec.template.spec.containers[0].resources}'`.
3. Banco lento: conexões esgotadas no pool aparecem como timeouts nos logs (`couldn't get a connection`).
4. Latência injetada: `APP_FAULT_LATENCY_MS`.

**Mitigação:** aumentar `autoscaling.maxReplicas` ou os requests; corrigir a causa no banco; reverter a versão se a regressão começou num deploy.

## Argo CD: Application travada em Progressing ou OutOfSync

```bash
kubectl -n argocd get application <app> -o jsonpath='{.status.conditions}'
kubectl -n argocd get application <app> -o jsonpath='{.status.operationState.message}'
```

Causas comuns neste laboratório:

- **CRD ainda não existe:** a Application depende de outra que ainda não terminou (ex.: `gateway-config` antes do `cert-manager`). As sync-waves e o retry resolvem sozinhos; se não, sincronize a dependência primeiro.
- **Recurso que nunca fica Healthy:** um `Certificate` sem emissor ou um `Gateway` sem `GatewayClass` aceita. `kubectl describe` no recurso mostra a condição.
- **Drift:** alguém alterou o cluster à mão. Com self-heal ligado o Argo CD desfaz; em prod (sem self-heal) aparece como OutOfSync até alguém sincronizar.

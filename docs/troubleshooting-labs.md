# Exercícios de troubleshooting

Cada cenário quebra o ambiente `api-dev` de um jeito diferente. O script pausa o sync automático do Argo CD, senão o self-heal desfaria a falha em segundos.

```bash
scripts/lab.sh <cenário>   # provoca a falha
scripts/lab.sh reset       # o Argo CD restaura o estado do Git
```

Tente diagnosticar só com `kubectl get`, `describe`, `logs`, `events` e o Grafana antes de abrir a resposta.

Comandos que resolvem a maioria dos casos:

```bash
kubectl -n api-dev get pods -o wide
kubectl -n api-dev describe pod <pod>              # seção Events no final
kubectl -n api-dev logs <pod> --previous           # logs do container que morreu
kubectl -n api-dev get events --sort-by=.lastTimestamp
kubectl -n api-dev rollout status deploy/api
```

---

### 1. `image`

**Sintoma:** um pod novo não sobe; os antigos continuam atendendo.

<details><summary>Resposta</summary>

`ImagePullBackOff`. O `describe` mostra `manifest unknown` ou `not found` para a tag. A API continua no ar porque o rolling update usa `maxUnavailable: 0`: o pod antigo só sai quando o novo fica pronto. Pergunta de entrevista associada: "por que o deploy quebrado não derrubou o serviço?".

Outras causas de `ImagePullBackOff` que valem conhecer: pacote privado no GHCR sem `imagePullSecrets`, rate limit do Docker Hub, arquitetura da imagem diferente da do nó.
</details>

### 2. `probe`

**Sintoma:** `rollout status` não termina; pods novos em `Running`, mas `0/1` em READY.

<details><summary>Resposta</summary>

A readiness aponta para um caminho inexistente e recebe 404. `describe` mostra `Readiness probe failed: HTTP probe failed with statuscode: 404`. O pod não entra nos Endpoints do Service, então não recebe tráfego, e o rollout fica parado esperando. Se fosse a **liveness**, o kubelet reiniciaria o container em loop.
</details>

### 3. `crash`

**Sintoma:** pod em `CrashLoopBackOff` com o contador de restarts subindo.

<details><summary>Resposta</summary>

`kubectl logs <pod> --previous` mostra o erro de validação do pydantic: `APP_DB_POOL_MAX` não é um inteiro. A aplicação falha no startup, antes de abrir a porta. O backoff entre reinícios cresce até 5 minutos, por isso o pod parece "parado" por um tempo.
</details>

### 4. `oom`

**Sintoma:** pods reiniciando sem nada de anormal no log da aplicação.

<details><summary>Resposta</summary>

`describe` mostra `Last State: Terminated, Reason: OOMKilled, Exit Code: 137`. O limit de 24 MiB está abaixo do que o Python precisa para subir. O log da aplicação não mostra nada porque quem mata o processo é o kernel (cgroup), não a aplicação. No Grafana, o painel *Memória vs limit* mostra o uso batendo no teto.
</details>

### 5. `quota`

**Sintoma:** o HPA pede 3 réplicas e só existem 2.

<details><summary>Resposta</summary>

Não há pod `Pending`: o pod nem chega a ser criado. O erro está nos eventos do ReplicaSet: `kubectl -n api-dev describe rs` mostra `exceeded quota: api-dev, requested: requests.cpu=900m, used: ..., limited: requests.cpu=2`. Diferença importante: `Pending` com `FailedScheduling` é falta de capacidade no **nó**; `exceeded quota` é limite do **namespace**, verificado na admissão.
</details>

### 6. `netpol`

**Sintoma:** pods param de ficar prontos; `/readyz` retorna 503.

<details><summary>Resposta</summary>

A NetworkPolicy da API foi removida e sobrou só o `default-deny` do namespace: a API não resolve DNS nem alcança o banco, e o Envoy também não alcança a API. Para confirmar de dentro do pod sem instalar nada na imagem:

```bash
kubectl -n api-dev debug -it <pod> --image=nicolaka/netshoot --target=api -- \
  sh -c 'nslookup api-db-rw; nc -zv api-db-rw 5432'
```

Lição: NetworkPolicy é aditiva. Sem nenhuma política o tráfego é livre; com `default-deny`, tudo que não estiver liberado explicitamente para.
</details>

### 7. `slo`

**Sintoma:** depois de uns minutos de tráfego, o alerta `ApiErrorBudgetBurnFast` aparece em Alertmanager e no Grafana.

<details><summary>Resposta</summary>

30% das requisições retornam 500 por falha injetada. Acompanhe no Prometheus `api:sli_errors:ratio_rate5m` subir primeiro e `ratio_rate1h` depois; o alerta só dispara quando as duas passam de 7,2% e a condição dura 2 minutos. Depois do `reset`, observe o alerta resolver assim que a janela de 5 minutos cai, mesmo com a de 1 hora ainda alta: é por isso que se usam as duas.
</details>

### 8. `latency`

**Sintoma:** o painel de latência mostra p95 perto de 450 ms; depois de 10 minutos, `ApiLatencyP95High` dispara.

<details><summary>Resposta</summary>

Latência injetada. Repare que a disponibilidade continua 100%: um serviço lento não aparece em SLO de erro, por isso existem os dois.
</details>

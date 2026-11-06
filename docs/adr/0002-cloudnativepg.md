# ADR 0002: PostgreSQL com CloudNativePG

**Status:** aceita · **Data:** 2026-11

## Contexto

A API precisa de PostgreSQL em dev e prod. O caminho mais comum em tutoriais é o chart Bitnami, mas desde agosto de 2025 as imagens versionadas da Bitnami foram movidas para `bitnamilegacy`, que não recebe atualizações, e o catálogo mantido passou a ser comercial.

## Decisão

Usar o operator CloudNativePG. Cada ambiente declara um recurso `Cluster` em `gitops/envs/<env>/manifests/database.yaml`; o operator cria os pods, os Services `-rw`/`-ro` e o Secret `api-db-app` com a `uri` de conexão consumida pela API.

## Consequências

- O Deployment da API não conhece senha nenhuma: referencia o Secret gerado pelo operator.
- Prod roda 2 instâncias com replicação e failover gerenciados pelo operator; dev roda 1.
- O padrão operator (CRD + controller reconciliando estado) fica demonstrado num caso real.
- O `monitoring.enablePodMonitor` do `Cluster` está depreciado no CNPG 1.30, por isso o PodMonitor é declarado à parte.
- Custo: mais um componente de plataforma; backups para object storage não foram configurados (ver Limitações no README).

## Alternativas consideradas

- **StatefulSet escrito à mão:** bom para aprender PVC e Service headless, mas failover, backup e upgrade ficariam por conta própria.
- **Imagens `bitnamilegacy`:** funcionam hoje, sem nenhuma correção de segurança daqui para frente.

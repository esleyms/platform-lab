# ADR 0001: Gateway API com Envoy Gateway

**Status:** aceita · **Data:** 2026-11

## Contexto

O laboratório precisa expor a API, o Grafana e o Argo CD por HTTPS. A escolha óbvia até 2025 seria o Ingress NGINX, mas o projeto foi aposentado pelo SIG Network em março de 2026: sem novas versões, sem correções de bugs e sem patches de segurança. Os artefatos continuam disponíveis, o que torna fácil instalar algo que não será mais corrigido.

## Decisão

Usar a Gateway API (`gateway.networking.k8s.io/v1`) com o Envoy Gateway como implementação, e o cert-manager emitindo o certificado do listener HTTPS.

- `GatewayClass` + `EnvoyProxy`: a plataforma define como os proxies são implantados (NodePort fixo para o kind).
- Um `Gateway` compartilhado em `envoy-gateway-system`, que só aceita `HTTPRoute` de namespaces com o label `platform-lab/gateway-access=true`.
- Cada time publica a própria `HTTPRoute` no seu namespace.

## Consequências

- A separação de papéis da Gateway API (infraestrutura, operação do cluster, aplicação) fica explícita nos recursos, algo que o `Ingress` resolvia com anotações específicas de cada controller.
- Redirecionamento HTTP para HTTPS, roteamento por caminho e TLS são campos padronizados, portáveis entre implementações.
- Custo: mais tipos de recurso para aprender, e o chart do Envoy Gateway só existe em registry OCI (exigiu declarar o repositório OCI no Argo CD).

## Alternativas consideradas

- **Ingress NGINX:** descartado pela aposentadoria.
- **Traefik:** suporta Ingress e Gateway API; seria uma escolha válida. O Envoy Gateway foi preferido por ser um projeto do próprio ecossistema Envoy focado só na Gateway API.
- **Fork mantido por terceiros do ingress-nginx:** resolve o curto prazo de quem já tem muitas regras, não faz sentido para um projeto novo.

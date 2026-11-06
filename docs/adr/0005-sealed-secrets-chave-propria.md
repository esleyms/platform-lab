# ADR 0005: Sealed Secrets com chave gerada fora do cluster

**Status:** aceita · **Data:** 2026-11

## Contexto

Por padrão o controller do Sealed Secrets gera o próprio par de chaves na primeira execução e renova a cada 30 dias. Num laboratório destruído e recriado com frequência, cada `make up` teria uma chave nova e os SealedSecrets já commitados deixariam de ser decifráveis.

## Decisão

O `scripts/bootstrap.sh` gera um par de chaves em `~/.config/platform-lab/` (fora do repositório) e o carrega no cluster como Secret com o label `sealedsecrets.bitnami.com/sealed-secrets-key=active` antes de o Argo CD instalar o controller. A renovação automática fica desligada (`keyrenewperiod: "0"`).

## Consequências

- `make seal` cifra offline com o certificado público, sem acessar o cluster.
- A chave privada vira um ativo a proteger: quem a tiver decifra todo segredo do repositório. Em produção ficaria num cofre (KMS, Vault) e teria rotação planejada.
- Segredos de bootstrap que não podem depender do próprio GitOps (senha do Grafana, chave do Sealed Secrets) são criados pelo bootstrap: é o problema clássico do "secret zero".

## Alternativas consideradas

- **External Secrets Operator + cofre externo:** melhor para produção, mas exigiria um cofre rodando fora do laboratório.
- **SOPS com age:** também versiona segredos cifrados; exigiria plugin no Argo CD.

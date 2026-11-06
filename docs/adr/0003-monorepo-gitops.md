# ADR 0003: Monorepo com código, chart e estado GitOps

**Status:** aceita · **Data:** 2026-11

## Contexto

O padrão mais citado de GitOps separa o repositório da aplicação do repositório de manifests. Num laboratório de portfólio, a prioridade é que quem lê veja o fluxo completo num lugar só.

## Decisão

Um repositório com `apps/` (código), `charts/` (empacotamento) e `gitops/` (estado desejado). O CI altera `gitops/envs/dev/values.yaml` com um commit feito pelo `GITHUB_TOKEN`.

## Consequências

- Commits feitos com o `GITHUB_TOKEN` não disparam novos workflows, o que elimina o loop "CI commita, CI roda de novo" sem precisar de `[skip ci]`.
- Os workflows filtram por caminho (`apps/api/**`, `gitops/**`), então mudar só manifests não rebuilda imagem.
- Prod é promovido por PR (workflow `promote`), o que dá revisão e trilha de auditoria.
- Custo: em uma organização real, permissões de escrita no estado de prod e no código ficariam misturadas. Branch protection e CODEOWNERS por diretório mitigam; a separação em dois repositórios resolve.

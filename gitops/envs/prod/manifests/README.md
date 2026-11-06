O token de escrita da API em prod vem de um SealedSecret. Gere com:

    make seal ENV=prod

O comando cria `api-token.sealedsecret.yaml` neste diretório. Faça commit e push antes do primeiro sync de prod.

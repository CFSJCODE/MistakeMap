# Prévia de coautoria — ChatGPT 6 Astra

Estado atualizado em 29/09/2026: APLICADA e confirmada no GitHub após autorização explícita do usuário para o commit e as liberações necessárias. Os objetos foram criados localmente e a main remota foi atualizada com proteção por SHA esperado. A main local foi preservada. As seções abaixo registram a prévia e as condições anteriores à aplicação.

## Resultado confirmado

- abcb950 → ad3da871fa04e11bd948a91e382b4da7d903f8b9
- cb0a4f2 → 515b65aa487939c0c17648f74ec63d90dcb472a8
- 348c4f4 → 05fac5c21a9dd33902cd151ed5717bf5babfe670
- Nova main remota: 4d0dfe3c7b7fc744b28c20784894f5b8e511ae21.
- As três mensagens publicadas foram consultadas pela API do GitHub e contêm Claude e ChatGPT 6 Astra.
- Árvores, autores, datas, ordem dos pais e 41 mensagens restantes preservados; todos os arquivos rastreados e os cinco arquivos localmente modificados mantiveram seus hashes.
- O conteúdo lógico dos 710 registros do índice permaneceu igual ao HEAD local; uma mudança binária do índice foi observada após o preparo, sem causa determinada e sem mudança de conteúdo staged.
- A liberação temporária ficou restrita a .git/**; a configuração original allowLegacyEdits=false foi restaurada byte a byte.
- Backup recuperável: historico-antes.bundle, verificado pelo Git. Mapeamento completo e validações: resultado.json.
- Nenhuma alteração de código foi publicada. A divergência preexistente da main local foi preservada.

Adicionar a assinatura abaixo aos três commits indicados, preservando o autor principal e a coautoria do Claude. O endereço proposto é um identificador genérico; a associação visual a uma conta do GitHub não foi verificada.

## Mensagens propostas

### abcb950621d6c627f310b0f0c238356b7af7b3eb

```text
docs: remove README da raiz

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
Co-Authored-By: ChatGPT 6 Astra <noreply@openai.com>
```

### cb0a4f2b72a2d5ec664140db8eca6c574c9daa60

```text
docs: remove README de .github

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
Co-Authored-By: ChatGPT 6 Astra <noreply@openai.com>
```

### 348c4f4d879b493704a10a22abb95ff3716e475e

```text
docs: adiciona README completo em .github

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
Co-Authored-By: ChatGPT 6 Astra <noreply@openai.com>
```

## Verificações e aplicação pendente

- Os três commits formam uma sequência ancestral da main publicada.
- A main remota foi consultada sem alteração e estava em 01ad880d65fb67bbb03fdd2acca3f5be9e7dd51f. Esse valor deve ser revalidado antes de qualquer aplicação.
- A alteração das mensagens muda os identificadores dos três commits e de 41 descendentes: 44 commits afetados, incluindo 6 merges. Nenhum desses 44 objetos possui cabeçalho gpgsig.
- Preservar árvores de arquivos, autores, responsáveis pelos commits, datas e todas as mensagens não selecionadas. Nos descendentes, alterar somente referências aos pais reescritos.
- A main local está em outra cadeia histórica, sem ancestral comum com origin/main. Não usar a main local como substituta do histórico publicado.
- Há cinco arquivos gerados do Flutter previamente modificados no diretório de trabalho. Devem permanecer intactos.
- A publicação exigiria atualização protegida por comparação do SHA remoto esperado, com cópia de segurança recuperável e validação das árvores antes da atualização. Nenhum push foi executado.

## Bloqueio de escrita

O AGENTS.md exige respeitar .reversa/reversa-config.json, que está com allowLegacyEdits=false. A gravação em .git/** está bloqueada. Somente o usuário pode editar essa configuração.

Liberação mínima sugerida para esta operação, a ser feita pelo usuário:

```json
{
  "version": 1,
  "allowLegacyEdits": true,
  "allowedPaths": [".git/**"]
}
```

Após a liberação, revalidar estado local e remoto antes de aplicar. Este documento não altera a configuração nem executa a reescrita.

Referência do formato: https://docs.github.com/en/pull-requests/how-tos/commit-changes/creating-a-commit-with-multiple-authors

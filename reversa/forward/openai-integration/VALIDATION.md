# Validação da integração preparada

Data: 29/09/2026. Estado: **preparada; não aplicada nem publicada**.

## Resultados

| Área | Evidência | Resultado |
|---|---|---|
| Backend IA | 19 testes de contratos/autenticação/validação | Passaram |
| Serviço completo local | Uma suíte com oito cenários; PGlite e Responses simulada | Passou |
| Upload | Sete testes de autenticação, formatos/tamanho, CORS, quotas e mensagens seguras | Passaram |
| Banco e RLS | 16 verificações sobre migrações base + alteração preparada | Passaram |
| Aplicação de arquivos | Quatro testes da política de caminhos/configuração | Passaram |
| Tipos do backend | Deno check de análise, prática, lote e upload | Passou |
| Frontend | 18 testes comportamentais: agregação, widgets e contratos HTTP | Passaram |
| Tipos do frontend | `dart analyze lib test` | Sem problemas encontrados |
| Capturas de prévia | Dois testes gerando três imagens de 360 px | Passaram |
| Visual | Formulário, gráficos e conexões em 360 px | Inspecionados; grafo corrigido para rótulos legíveis |
| Preflight de aplicação | 33 arquivos; hashes dos originais preservados | Bloqueado corretamente por `allowLegacyEdits: false` |

O serviço local verificou análise textual, persistência conjunta da correção e dos erros, consulta de resultado sem nova chamada, recusa de outro proprietário, falha/retry sem duplicação, última execução expirada em estado final e geração de três exercícios com gabaritos privados. O provedor externo foi substituído por uma resposta de teste dentro do processo; não houve chamada real à OpenAI.

Os testes do banco verificaram acesso isolado entre dois usuários sintéticos, recusa de alteração dos resultados, gabaritos e uso privados, estados de análise controlados pelo servidor, referências entre usuários recusadas, origem/hash de anexos e enunciados protegidos contra alteração depois de utilizados.

## Revisão independente

Foram corrigidos o contrato de tamanho do upload, repetição da finalização após resposta perdida, integridade da imagem, recuperação de execução expirada, bloqueio da fila por limite individual, ordem de locks, alteração de enunciado após diagnóstico e mensagens incorretas de estado. A revisão final não encontrou pendência bloqueante entre esses itens. Isso não é uma auditoria exaustiva nem substitui os testes remotos.

## Limites da evidência

- O PGlite local usa PostgreSQL 18.3; o projeto remoto consultado usa PostgreSQL 17.6.1. Autenticação e funções preexistentes de limitação de anexos foram simuladas no ensaio SQL.
- Não foi exercitada concorrência com múltiplas sessões PostgreSQL reais.
- Não houve upload real ao R2, migração/publicação remota, alteração de secrets, autenticação de aluno real ou validação pedagógica de um modelo OpenAI.
- A geração de exercícios pode ser repetida após timeout e consumir outra chamada. A análise de uma mesma tentativa tem proteção específica; não há promessa de idempotência geral.
- `flutter analyze` apresentou falha interna de protocolo LSP no caminho Windows com Unicode. A análise direta equivalente por `dart analyze lib test` passou; `flutter pub get --offline` também passou.
- Nenhum arquivo original de implementação foi substituído. Alterações anteriores nos registradores de plugins Flutter foram preservadas.

## Prévia

As imagens em `staged/appmistakemap/test/previews/` foram geradas por testes e exibem a faixa **PRÉVIA · DADOS SINTÉTICOS**. Não são resultados de alunos reais nem evidência de integração já publicada.

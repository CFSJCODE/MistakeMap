# Caderno local e sincronização offline

## Visão Geral

Esta unit mantém um caderno de erros manual em SQLite e oferece cache, fila persistente e sincronização de operações com Supabase quando a rede retorna. O caderno funciona separado dos eventos de análise que alimentam o mapa de IA. 🟢

## Responsabilidades

- Criar, listar, editar e excluir registros locais por usuário. 🟢
- Migrar o banco local da versão 1 para 2 sem perder dados. 🟢
- Manter cache por usuário/chave e fallback somente em falha de rede. 🟢
- Enfileirar alterações offline, reenviar em ordem e tratar conflitos. 🟢
- Incorporar registros manuais no mapa de fragilidades. 🔴

## Regras de Negócio

- Todas as operações locais de caderno são filtradas por `usuario_id`. 🟢
- Falha de rede pode usar cache/fila; falha de RLS ou validação é exibida e não tratada como offline. 🟢
- Reenvios usam UUID estável/upsert para evitar duplicação; conflito do servidor não é repetido silenciosamente. 🟢
- O caderno manual não cria atualmente eventos de erro no mapa de IA. 🟢

## Requisitos Funcionais

| ID | Requisito | Prioridade | Critério de Aceite |
|---|---|---|---|
| RF-01 | Manter CRUD local de disciplinas e registros de erro. 🟢 | Must | Operações retornam registros do usuário correto. |
| RF-02 | Atualizar schema local com cache e fila mantendo dados anteriores. 🟢 | Must | Upgrade v1→v2 cria tabelas novas e conserva registros antigos. |
| RF-03 | Usar cache por conta e chave em falha de rede. 🟢 | Should | Cache de outra conta nunca é apresentado. |
| RF-04 | Sincronizar operações pendentes em ordem e sem duplicar. 🟢 | Must | Reexecução da fila mantém um único efeito remoto. |
| RF-05 | Expor conflitos/recusas do servidor para ação do estudante. 🟢 | Must | Falha não desaparece nem entra em retry ilimitado. |
| RF-06 | Converter registros do caderno em evidências no mapa de IA. 🔴 | Could | Integração não está definida no briefing; manter fontes separadas até decisão. |

## Requisitos Não Funcionais

| Tipo | Requisito inferido | Evidência no código | Confiança |
|---|---|---|---|
| Integridade | Transações e parâmetros protegem alterações SQLite e escopo local. | `appmistakemap/lib/local/registro_erro_dao.dart` | 🟢 |
| Disponibilidade | Fila persistente pode retomar depois de reconexão/retorno ao app. | `appmistakemap/lib/sync/sincronizador.dart` | 🟢 |
| Desempenho | Timeout de consulta permite fallback para cache. | `appmistakemap/lib/sync/sincronizador.dart` | 🟢 |

## Critérios de Aceitação

```gherkin
Dado um estudante autenticado
Quando cria, lista, edita ou exclui um registro no caderno
Então as operações SQLite persistem os dados apenas no escopo dessa conta

Dado um banco local na versão 1 com registros existentes
Quando o app abre a versão 2
Então acrescenta cache/fila sem apagar os registros antigos

Dado uma operação de sincronização criada offline
Quando a conectividade retorna
Então ela é enviada uma vez com identificador idempotente

Dado uma falha de autorização ou validação remota
Quando a fila sincroniza
Então registra a recusa visivelmente e não a disfarça como falta de rede

Dado uma consulta remota temporariamente indisponível
Quando há cache válido da mesma conta e chave
Então o app apresenta o cache sem misturar dados de outra conta
```

## Prioridade (MoSCoW)

| Requisito | MoSCoW | Justificativa |
|---|---|---|
| CRUD local e isolamento por usuário | Must | Finalidade central do caderno offline. |
| Fila idempotente e tratamento de conflito | Must | Evita perda/duplicação na reconexão. |
| Cache com fallback em falha de rede | Should | Melhora disponibilidade mantendo validação remota como fonte principal. |
| Integração do caderno com o mapa | Could | Exige decisão de domínio e não está implementada nem explicitamente requerida. |

## Rastreabilidade de Código

| Arquivo | Função / Classe | Cobertura |
|---|---|---|
| `appmistakemap/lib/local/banco_local.dart` | Abertura e migração SQLite | 🟢 |
| `appmistakemap/lib/local/registro_erro_dao.dart` | CRUD e filtro por usuário | 🟢 |
| `appmistakemap/lib/sync/sincronizador.dart` | Cache e processamento da fila | 🟢 |
| `appmistakemap/lib/sync/armazem_sync.dart` | Persistência de operações pendentes | 🟢 |
| `appmistakemap/lib/sync/sobreposicao.dart` | Aplicação otimista das operações pendentes | 🟢 |

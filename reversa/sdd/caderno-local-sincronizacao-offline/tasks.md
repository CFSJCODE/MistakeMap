# Caderno local e sincronização offline — Tarefas de Implementação

## Pré-requisitos

- [ ] Declarar drivers SQLite para Android, desktop e Web no pacote Flutter.
- [ ] Definir modelo remoto compatível para operações que sincronizam.
- [ ] Manter escopo de usuário em cache, banco e fila.

## Tarefas

- [ ] T-01, Criar banco local com foreign keys e migração aditiva v1→v2.
  - Origem no legado: `appmistakemap/lib/local/banco_local.dart`
  - Critério de pronto: banco antigo mantém dados e as tabelas novas são criadas uma vez.
  - Confiança: 🟢
- [ ] T-02, Implementar CRUD do caderno com isolamento por usuário e filtros.
  - Origem no legado: `appmistakemap/lib/local/registro_erro_dao.dart`
  - Critério de pronto: usuário não lista, altera nem exclui registros de outra conta.
  - Confiança: 🟢
- [ ] T-03, Implementar cache e fallback apenas para falha transitória de rede.
  - Origem no legado: `appmistakemap/lib/sync/sincronizador.dart`
  - Critério de pronto: cache tem chave/usuário e erro de permissão é propagado.
  - Confiança: 🟢
- [ ] T-04, Persistir e processar fila serial com UUID estável e upsert.
  - Origem no legado: `appmistakemap/lib/sync/armazem_sync.dart`, `appmistakemap/lib/sync/sincronizador.dart`
  - Critério de pronto: interrupção/reexecução não duplica operação remota.
  - Confiança: 🟢
- [ ] T-05, Apresentar recusas e conflitos para resolução explícita.
  - Origem no legado: `appmistakemap/lib/sync/sincronizador.dart`, `appmistakemap/lib/sync/sobreposicao.dart`
  - Critério de pronto: operação rejeitada é visível e não entra em loop de retry.
  - Confiança: 🟢
- [ ] T-06, Definir integração opcional entre registro local e mapa de IA.
  - Origem no legado: `appmistakemap/lib/local/registro_erro.dart`, `appmistakemap/lib/ai/analysis_models.dart`
  - Critério de pronto: regra de origem/validação e consentimento estão aprovados antes de sincronizar evidências.
  - Confiança: 🔴

## Tarefas de Teste

- [ ] TT-01, Testar criação/abertura, upgrade v1→v2 e foreign keys.
- [ ] TT-02, Testar CRUD e isolamento em duas contas.
- [ ] TT-03, Testar fallback do cache e propagação de erro não relacionado à rede.
- [ ] TT-04, Testar fila em ordem, reexecução, reconexão, conflito e falha definitiva.
- [ ] TT-05, Testar que dados locais não cruzam usuários após logout/login.

## Tarefas de Migração de Dados

- [ ] TM-01, Preservar registros e IDs existentes durante upgrade local; não substituir a base por uma recriação vazia.

## Ordem Sugerida

1. Schema local e DAO precedem cache/fila.
2. Isolamento e idempotência devem passar antes de habilitar sincronização automática.
3. Decidir relação com o mapa somente após esclarecer semântica de validação.

## Lacunas Pendentes (🔴)

Definir se o caderno continua independente ou se registros escolhidos pelo estudante alimentam o mapa; estabelecer transformação e auditoria antes de implementar.

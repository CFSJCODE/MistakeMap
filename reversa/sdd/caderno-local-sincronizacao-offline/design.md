# Caderno local e sincronização offline — Design Técnico

## Interface

| Símbolo | Entrada | Retorno | Observação |
|---|---|---|---|
| `BancoLocal._abrir` | nenhuma | `Future<Database>` | Abre banco por plataforma e aplica upgrade. 🟢 |
| `RegistroErroDao.inserir` | `RegistroErro` | `Future<int>` | Insere em transação. 🟢 |
| `RegistroErroDao.listar` | `usuarioId`, `ocultarRevisados` | `Future<List<RegistroErro>>` | Filtra pelo dono. 🟢 |
| `RegistroErroDao.atualizar/excluir` | Registro ou usuário+ID | `Future<int>` | Escopo por usuário. 🟢 |
| `Sincronizador.consultar` | usuário, chave, consulta remota | `Future<Object?>` | Atualiza cache e usa fallback de rede. 🟢 |
| `Sincronizador.sincronizar` | nenhuma | `Future<void>` | Processa fila serialmente. 🟢 |
| `sobreporExercicios` | dados remotos, fila e usuário | matérias/exercícios | Aplica operações locais pendentes para leitura otimista. 🟢 |

## Fluxo Principal

1. `BancoLocal` abre a base `mistakemap_local.db`; Android usa SQLite, Windows/Linux FFI e Web SQLite WASM/IndexedDB. 🟢 (`appmistakemap/lib/local/banco_local.dart`)
2. Banco versão 2 preserva `disciplinas` e `registros_erro` da versão 1 e acrescenta `cache_consultas` e `fila_sync`. 🟢
3. DAO executa CRUD parametrizado e limita cada consulta pelo `usuario_id`. 🟢 (`registro_erro_dao.dart`)
4. `Sincronizador.consultar` tenta remoto, atualiza cache e usa cache apenas quando a falha é de rede/timeout. 🟢
5. Escrita sem conexão é persistida com operação, usuário, dados, UUID e tentativas na fila. 🟢 (`armazem_sync.dart`)
6. Ao reconectar ou retomar o app, sincronizador envia operações em ordem, com identidade estável e upsert remoto. 🟢
7. Recusa de autorização/validação é registrada para ação do usuário; conflitos obedecem ao servidor. 🟢

## Fluxos Alternativos

- **Sem rede:** manter escrita na fila e leitura do cache da mesma conta. 🟢
- **Timeout remoto:** usar cache existente; sem cache, propagar erro. 🟢
- **Conflito de edição:** a versão do servidor prevalece; edição de exercício analisado pode ser recusada. 🟢
- **Falha definitiva:** manter estado de erro para ação do estudante e não reenviar automaticamente. 🟢
- **Mudança de usuário:** a fila/cache devem ser filtrados pela identidade atual. 🟢

## Dependências

- `sqflite`, `sqflite_common_ffi`, `sqflite_common_ffi_web`: persistência multiplataforma. 🟢
- `shared_preferences`: preferência de ocultar registros revisados. 🟢
- Supabase REST/Realtime: origem remota e atualização de dados. 🟢
- `appmistakemap/lib/ai/analysis_repository.dart`: sincronização de tentativas e análise. 🟢

## Decisões de Design Identificadas

| Decisão | Evidência no código | Confiança |
|---|---|---|
| Cache isolado por usuário e chave da consulta | `appmistakemap/lib/sync/sincronizador.dart` | 🟢 |
| UUIDs estáveis e upsert para reenvio idempotente | `appmistakemap/lib/sync/sincronizador.dart` | 🟢 |
| Retry de rede com sondagem exponencial e teto de intervalo | `appmistakemap/lib/sync/sincronizador.dart` | 🟢 |
| Conflito não sobrescreve silenciosamente o servidor | `appmistakemap/lib/sync/sobreposicao.dart` | 🟢 |
| Caderno manual é separado dos eventos de análise | `appmistakemap/lib/local/registro_erro.dart`, `appmistakemap/lib/ai/analysis_models.dart` | 🟢 |

## Estado Interno

SQLite mantém disciplinas, registros, cache e fila. A fila inclui usuário, operação, dados, imagem opcional, situação e número de tentativas. Cache e registros carregados não devem cruzar contas. 🟢

## Observabilidade

Estados de sincronização e recusas ficam disponíveis à interface; uma telemetria agregada específica da unit não foi confirmada. 🟡

## Riscos e Lacunas

- 🔴 Não existe regra para converter um registro manual em evento confirmado do mapa.
- 🟡 Caderno local e histórico Supabase são fontes paralelas; UX deve indicar a diferença.
- 🟢 A cobertura de testes inclui upgrade, isolamento, CRUD, cache, reconexão, conflito e idempotência.

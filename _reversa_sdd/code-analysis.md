# Análise técnica — MistakeMap

> Nível: Essencial. Evidências extraídas do código-fonte; lacunas estão
> identificadas como pontos de validação, não como comportamento confirmado.

## Autenticação e navegação Flutter

### Fluxo de autenticação

1. `MistakeMapApp` inicia o `AuthGate`, que observa `onAuthStateChange`.
2. Durante a inicialização, o app mostra um indicador de carregamento.
3. Sem sessão atual, mostra `TelaCadastro`, que alterna entre login e criação
   de conta por e-mail e senha.
4. No cadastro, se o Supabase não abrir uma sessão imediatamente, a interface
   pede confirmação do e-mail.
5. Com sessão, `_CarregadorDePerfil` busca `profiles.role` e constrói `AppUser`.
   O papel padrão é `user`; somente `admin` habilita a aba administrativa.
6. Uma falha de refresh no stream de autenticação não encerra uma sessão ainda
   válida: `AuthGate` consulta `currentSession`.

### Login Google

- Web e Android exibem a opção; outras plataformas não a exibem.
- Antes de abrir o OAuth, `GoogleSignInService` verifica
  `/auth/v1/settings` com a chave pública e timeout.
- Web retorna à origem e caminho atuais, sem query nem fragmento; nativo usa
  `io.supabase.mistakemap://login-callback/`.
- Provedor desabilitado, configuração indisponível e falha ao abrir são
  tratados com mensagens distintas.

### Navegação

- `TelaNavegacao` mantém Início, Meus exercícios, Mapa de erros e Caderno de
  erros como destinos centrais; Administração é condicional ao papel.
- O Mapa abre o shell de IA como rota dedicada. A tela Sobre também é aberta
  como rota.
- Em janelas desktop usa trilho lateral; em telas menores usa navegação
  inferior e menu “Mais”. O retorno do sistema seleciona Início antes de sair.
- `NavigationPages` mantém as telas no shell e os testes verificam estado,
  acessibilidade de toque, navegação e apresentação em larguras distintas.

### Dados e regras

| Entidade | Campos | Regras observadas |
|---|---|---|
| `AppUser` | `id: String`, `email: String`, `role: String` | `isAdmin` é verdadeiro somente para `role == 'admin'`; papel padrão `user`. |
| Sessão Supabase | usuário e tokens geridos pelo SDK | Uma falha transitória do stream não remove a sessão atual. |

### Lacunas a validar

- Não foi localizado fluxo de recuperação de senha na tela de autenticação.
- A consulta de perfil captura qualquer exceção e segue com papel `user`; isso
  evita conceder privilégios, mas pode ocultar indisponibilidade do perfil.
- Os testes cobrem o gate de sessão, falha de refresh, OAuth e navegação
  responsiva. Não foi possível executá-los neste ambiente: o runner do VS Code
  não executou testes e o comando `flutter` não está disponível no PATH.

## Exercícios, análise, mapa de erros e prática

### Registro e análise

- `ExerciseSubmissionView` permite registrar matéria, enunciado, resposta e
  dificuldade opcional; a foto pode complementar ou substituir enunciado e
  resposta. A captura aceita câmera ou galeria.
- O repositório cria a tentativa no Supabase, envia a imagem por URL
  pré-assinada e solicita `analyze-attempt`. Imagens JPEG, PNG e WebP são
  reconhecidas pela assinatura binária e limitadas a 8 MB.
- Se não houver conexão, a tentativa entra na fila local e deve ser enviada e
  analisada após reconexão. Repetir uma análise em andamento para o mesmo ID
  compartilha a mesma chamada.
- O detalhe mostra correção sugerida, explicação, transcrição da foto,
  evidências de cada erro e confiança reportada pela IA; a interface avisa que
  a análise é uma sugestão e deve ser conferida pelo estudante.

### Mapa e agregações

- `ErrorInsights` remove duplicações por ID de tentativa e agrupa erros por
  matéria, conceito normalizado e categoria. Frequências contam tentativas
  distintas, não rótulos repetidos.
- O grafo apresenta matéria → conceito → tipo de erro. Arestas representam
  coocorrência na tentativa e largura representa frequência; não inferem
  relações causais nem pré-requisitos.
- A tela filtra por matéria e por todo o histórico, 30 dias ou 7 dias. As
  visualizações são gráficos de frequência, nuvem de conceitos, conexões e
  lista de tentativas.
- Categorias Flutter: cálculo, conceito, sinal, interpretação, procedimento,
  unidade e outro.

### Prática

- A tela solicita de 3 a 5 exercícios, permite escolher matéria e categoria
  de erro e carrega práticas já salvas.
- O cliente não recebe chave de resposta. Cada exercício abre o formulário
  comum de resolução e análise individual, sem uma rodada de quiz.
- A análise do cliente não exibe resumo final de rodada, total/percentual de
  acertos e erros nem um botão para iniciar nova rodada a partir dos
  resultados. Também não foram localizados flashcards ou revisão teórica
  integrada.

### Lacunas a validar

- O mapa mostra filtros temporais, mas não uma série temporal ou evolução
  explícita do estudante.
- Não há fluxo visível para o estudante aceitar ou rejeitar/corrigir a
  classificação da IA.
- A tela menciona diagnóstico quando não há histórico de erros; é necessário
  verificar no backend se os exercícios gerados sempre se fundamentam em
  exercícios já existentes, conforme requisito do produto.
- O fluxo atual é prática individual analisada por IA, não quiz online com
  métricas de rodada. A implementação dessa entrega pode usar tentativas e
  classificações existentes, mas precisa preservar a regra de não expor
  respostas corretas antes da resolução.
- Testes unitários e de widgets cobrem agregação, estados, formulário, prática
  e contratos do repositório. Não puderam ser executados: `flutter` não está
  disponível no PATH.

## Caderno local e sincronização offline

### Persistência local

- `BancoLocal` abre `mistakemap_local.db` na versão 2. A versão 1 contém
  `disciplinas` e `registros_erro`; a versão 2 acrescenta `cache_consultas` e
  `fila_sync`. `onUpgrade` adiciona as novas tabelas sem reescrever o schema
  anterior e cada conexão ativa `PRAGMA foreign_keys`.
- Android usa SQLite nativo; Windows/Linux usam FFI; Web usa SQLite WASM no
  IndexedDB. Shared Preferences guarda o filtro “ocultar revisados”.
- O DAO implementa CRUD com transações, parâmetros SQL e escopo por
  `usuario_id`; disciplina é reaproveitada por nome e disciplinas vazias são
  removidas.
- O caderno usa uma taxonomia local independente (conceitual, cálculo,
  interpretação, atenção) e não grava diretamente no grafo da análise por IA.

### Cache e fila Supabase

- Leituras tentam Supabase primeiro, com limite de 12 segundos, gravam cache
  local por usuário/chave e usam o último valor em falha de rede.
- Criação, edição, exclusão e upload de foto podem entrar na fila SQLite.
  UUIDs estáveis e upsert idempotente evitam duplicação após reconexão.
- A fila é enviada sequencialmente; rede indisponível agenda sondagem
  exponencial de 5 segundos até 1 minuto, retorno do app ao primeiro plano e
  respostas remotas podem disparar sincronização/atualização.
- Tentativas são analisadas após envio. Realtime escuta INSERT/UPDATE do
  próprio usuário em `subjects`, `attempts` e `attempt_analyses`.
- Conflitos obedecem ao servidor. Edição offline de exercício já analisado é
  descartada com aviso; outras recusas ficam marcadas como erro para ação do
  estudante.

### Dados e cobertura

| Entidade/tabela | Campos principais |
|---|---|
| `disciplinas` | `id`, `usuario_id`, `nome` (único por usuário) |
| `registros_erro` | disciplina, título, descrição, tipo, revisado e datas |
| `cache_consultas` | usuário, chave, JSON e atualização |
| `fila_sync` | usuário, operação, JSON, imagem opcional, situação e tentativas |

Testes cobrem schema e upgrade v1→v2, CRUD e isolamento por conta, filtro
persistente, cache, fila, reconexão, conflitos e idempotência. A execução
continua bloqueada pela ausência de `flutter` no PATH.

### Lacuna de integração

O caderno manual funciona offline, mas é separado do mapa e dos insights de IA.
Se a expectativa for que registros manuais também alimentem o grafo, será
necessário definir uma integração de domínio; isso não ocorre no código atual.

## Administração, métricas e apresentação

- `AdminMetricsPanel` tenta carregar snapshot global por RPC; se falhar,
  recorre a contagens submetidas ao RLS e deixa explícito que não são globais.
- O painel exibe contas, exercícios, tentativas/envios, processamento,
  solicitações de análise/prática, falhas, telemetria por modelo Gemini,
  consumo/cotas R2 e Supabase Storage.
- Realtime e conferência a cada 30 segundos são usados em Wi-Fi; rede móvel
  ou desconhecida limita leitura a uma hora; offline pausa atualização. A aba
  inativa e o app em segundo plano também suspendem eventos.
- Telemetria parcial ou ainda não ativada é exibida como indisponível, sem
  tratar quota desconhecida como saldo zero.
- `TelaSobre` inclui missão, visão, valores, dois membros da equipe,
  responsabilidades e stack. A marca, tokens, controles e transições são
  compartilhados entre as telas Fluent e Material; há suporte a movimento
  reduzido e layouts adaptativos.
- Testes cobrem a política de atualização por conectividade, painel suspenso
  em rede móvel, cotas parciais e limites de layout. Execução impedida pela
  ausência do Flutter CLI neste ambiente.

### Lacuna relacionada às entregas

As métricas existentes são de operação/administração, não de desempenho do
estudante ao final de um quiz. O código de UI disponível não apresenta taxa de
acerto/erro por rodada.

## Edge Functions, contratos de IA e testes

### Fluxo de análise

- `analyze-attempt` e `generate-practice` validam o JWT consultando o endpoint
  confiável do Supabase Auth; a chave de serviço e os segredos do Gemini/R2
  permanecem no backend. Os pedidos têm corpo limitado, validação de IDs,
  CORS restrito e respostas sem cache.
- A análise confere que tentativa, exercício e matéria pertencem ao usuário,
  reivindica o processamento com lock/lease e limite diário, valida até três
  imagens por assinatura e SHA-256 e chama o Gemini com schema JSON
  estruturado e fallback entre modelos.
- A resposta validada salva análise e correção, cria/conecta conceitos,
  registra eventos de erro como `pending` e registra acertos sugeridos pela IA
  como eventos de domínio. `is_correct: null` permanece aguardando revisão.
- O processador em lote usa segredo de cron, ignora usuários sem cota e
  processa uma tentativa por execução. O endpoint de upload gera URL R2
  assinada e reserva cota; `/health` verifica PostgreSQL e R2.

### Geração e priorização da prática

- `generate-practice` lê até 50 análises incorretas prévias da matéria do
  usuário, filtra opcionalmente pela categoria e prioriza conceitos por
  frequência ponderada pela recência (meia-vida de 14 dias), descontando até
  três acertos posteriores ao erro mais recente.
- Quando existem erros pendentes, a IA recebe categoria, conceito e trecho
  de evidência dos erros associados aos exercícios-fonte. Os IDs dessas
  tentativas são salvos em `practice_sets.source_attempt_ids`.
- **Lacuna confirmada:** o prompt de geração não recebe os enunciados originais
  nem as soluções dos exercícios-fonte. Assim, os itens são orientados por
  conceitos/evidências, não por referências completas dos exercícios
  existentes. Sem erros pendentes, o prompt usa apenas o nome da matéria e
  solicita exercícios diagnósticos; esse caminho não está fundamentado em
  exercícios anteriores.
- O contrato limita a rodada a 3–5 exercícios inéditos, exige conceito focal
  válido e guarda respostas e explicações em `practice_answer_keys`, sem
  retorná-las ao cliente. A prática é persistida, mas a interface ainda não
  oferece um resultado agregado por rodada.

### Taxonomia e cobertura

- As categorias de erro são cálculo, conceito, sinal, interpretação,
  procedimento, unidade e outro. Negações lógicas e condições de contorno não
  possuem categorias próprias no contrato atual.
- Os testes Deno cobrem validação de schemas, ranking e recuperação, limites,
  autenticação, CORS, uploads, hash de imagem, fallback do Gemini e rejeição
  de chamadas não autenticadas. Os 33 testes Deno passaram; os testes Flutter
  continuam pendentes porque o Flutter CLI não está disponível no PATH.

## Banco PostgreSQL, migrações e RLS

### Modelo de dados

As 22 migrações versionadas em `appmistakemap/database/supabase/migrations/`
definem o banco Supabase canônico. O modelo principal é orientado a eventos:
matéria → conceitos/grafo → exercícios/tentativas → correções, erros e
evidências de domínio.

| Entidade | Campos e relações principais |
|---|---|
| `subjects` | `id`, `user_id`, `name`, `description`, `created_at`; matéria pertence a usuário. |
| `concepts` | `id`, `subject_id`, `name`, `description`, `importance`, `created_at`. |
| `concept_edges` | `from_concept_id`, `to_concept_id`, `relation`; aresta direcionada, sem auto-loop e única por par/relação. |
| `exercises` | `id`, `subject_id`, `source`, `prompt_text`, `difficulty`, `created_at`. |
| `exercise_concepts` | ligação N:N entre exercício e conceito, com `weight`. |
| `attempts` | `id`, `exercise_id`, `user_id`, `solution_text`, `answer`, `attempted_at`, `status`, `version`. |
| `attempt_analyses` | análise JSON, `model`, `pipeline_version`, usuário/matéria/tentativa; uma por tentativa. |
| `corrections` | `attempt_id`, `reference_text`, anexo opcional, `reviewed_by`, data. |
| `error_types` / `error_events` | taxonomia compartilhada e evento por tentativa/conceito, com evidência, confiança e estado `pending/confirmed/rejected/superseded`. |
| `mastery_events` | evento por conceito/tentativa com `outcome`, usado como evidência temporal. |
| `practice_sets` | usuário/matéria, `source_attempt_ids`, quantidade (3–5), modelo e data. |
| `practice_answer_keys` | resposta, explicação e conceito focal ligados ao exercício e conjunto; conteúdo privado do servidor. |
| `profiles` | perfil acadêmico, `role` (`user`/`admin`) e `auth.users.id`. |
| Pipeline | `attempt_assets`, `processing_runs`, `ocr_artifacts` e `audit_log` registram uploads, leases/retries, OCR e trilha de auditoria. |
| Operação | `ai_daily_usage`, `rate_limits`, `r2_quota_usage`, `storage_alert_state` e `r2_alert_state` guardam cotas, rate limit e estado de alertas. |

### Propriedade e políticas

- RLS está habilitada nas tabelas do domínio. Matérias/tentativas usam
  `user_id = auth.uid()`; conceitos, exercícios, relações e eventos derivam
  propriedade por suas FKs até matéria ou tentativa.
- A migração de IA restringe `attempt_analyses` e `practice_sets` à leitura
  pelo proprietário e concede escrita privilegiada ao `service_role`.
  `practice_answer_keys` e `ai_daily_usage` não concedem acesso ao cliente.
  `processing_runs`, `ocr_artifacts`, `audit_log`, limites e estados de alerta
  não têm política de cliente.
- `error_types` é uma taxonomia global legível por usuários autenticados.
  Resultados de IA em `corrections`, `error_events` e `mastery_events` são
  somente leitura para o cliente; escrita é reservada ao backend.
- `attempt_assets` só pode ser criado pelo dono enquanto a tentativa está em
  `uploading`; caminho deve estar sob o UUID do usuário e SHA-256 deve ser
  hexadecimal de 64 caracteres.
- O perfil limita a alteração normal ao próprio usuário; `is_admin()` usa
  `SECURITY DEFINER` para evitar recursão de RLS. A função de criação automática
  atribui papel `user`; a cópia pública da migração foi sanitizada e não
  contém bootstrap pessoal de administradores.

### Integridade, automação e histórico

- `guard_attempt_ai_state` impede que o cliente forje status/versão da análise;
  `guard_analyzed_exercise` impede editar enunciado ou matéria depois de uma
  tentativa ou gabarito de prática, preservando a validade dos resultados.
- O rate limit usa janela fixa de 60 segundos, padrão de 300 inserções por
  usuário, aplicado por triggers em tabelas de escrita. Funções internas têm
  `search_path` fixo e privilégios `EXECUTE` revogados; `check_rate_limit` é
  a exceção disponibilizada a usuários autenticados.
- `pg_cron` e `pg_net` executam monitoramento de saúde, quota e alertas de
  armazenamento. A coleta R2 foi dividida entre disparo e processamento
  posterior porque a coleta síncrona de resposta excedia o timeout. O limite
  de uploads Supabase Storage também é aplicado por trigger.
- O README do banco alerta que a pasta é o histórico canônico: versões já
  aplicadas não devem ser reexecutadas ou reescritas. Parte das migrações foi
  reconstruída para conciliar o histórico remoto; o seed antigo depende de um
  usuário já existente, então bootstrap de banco vazio não está comprovado.

### Lacunas relacionadas ao produto

- **Validação do estudante:** a análise grava eventos `pending`, mas a migração
  deliberadamente não concede escrita ao cliente e declara que um fluxo
  auditável de revisão ainda precisa ser criado. Não há endpoint/RPC de aceite,
  rejeição ou correção da classificação.
- **Grafo:** `concept_edges` modela relações direcionadas, mas a tela atual
  constrói visualização de coocorrência; não há evidência de preenchimento ou
  uso de pré-requisitos pelo fluxo de análise.
- **Rodadas de quiz:** `practice_sets` registra geração e tentativas-fonte,
  mas não há entidade de rodada/respostas/resumo; métricas de quiz não são
  persistidas como uma sessão.
- **Rastreabilidade:** `source_attempt_ids` é um array UUID, não uma relação
  com FK; integridade referencial e consulta por exercício-fonte não são
  garantidas pelo schema atual.

## Worker Rust arquivado

### Estado e responsabilidade histórica

- `BACKEND.md` registra a migração do Fly.io para Edge Functions em 28/09/2026.
  O worker (`axum`/`sqlx`/AWS SDK) permanece como referência, mas não é o
  caminho ativo do app. O pipeline de IA funcional está em
  `supabase/functions/`; não reativar este worker como substituto sem
  reconstruir e validar o fluxo completo.
- `main` conecta ao Postgres e R2, carrega uma chave ES256 do JWKS do Supabase
  na inicialização e expõe `/health`, `/upload-url` e `/process-batch`.
  `/process-batch` usa segredo compartilhado com comparação em tempo constante;
  `/upload-url` valida JWT e reserva cota R2. Configuração é obrigatória via
  ambiente, com porta 8080 padrão.
- `run_batch` processa até cinco tentativas `pending`, usa
  `FOR UPDATE SKIP LOCKED`, baixa assets R2 e contabiliza operações Class A/B
  e bytes. `attempts.rs` controla concorrência por `version`.

### Limite funcional e divergências

- **Lacuna crítica para reativação:** `pipeline.rs` mantém `TODO`s para OCR,
  persistência de artefatos OCR, chamada LLM e gravação de erros; depois de
  baixar os arquivos, o código chama `mark_completed`. Portanto, o worker pode
  declarar concluída uma tentativa sem analisá-la.
- Falhas são gravadas como `retryable_failed`, mas `fetch_pending` seleciona
  somente `pending`; o retry descrito pela documentação não é efetivamente
  implementado nesse caminho. O fluxo também não aplica lease/retry limit.
- O upload legado aceita PDF, enquanto o contrato Edge/RLS ativo aceita apenas
  JPEG, PNG e WebP; não são contratos intercambiáveis.
- Não foram encontrados testes Rust em `worker/src`. O `fly.toml` descreve o
  deploy antigo, mas a documentação atual aponta Edge Functions como produção.
  A referência de deploy no Fly.io está obsoleta e não deve ser seguida sem
  revisão dos contratos, segurança e estados.

## CI/CD e deploy Web

- `.github/workflows/ci.yml` roda em PR (sem filtro de caminhos), push no
  `main` exceto mudanças apenas em Markdown e execução manual. Os jobs cobrem
  `deno check`/testes Deno, `flutter analyze`/format/test e
  `cargo check`/Clippy/test; versões fixadas: Deno 2.9.x, Flutter 3.47.2 e
  Rust 1.98.1.
- `.github/workflows/supabase-functions-deploy.yml` repete os testes Deno como
  gate e publica as Edge Functions a partir de `main`. As chaves de runtime
  permanecem nos secrets do Supabase; o workflow recebe somente acesso e
  identificação do projeto.
- `.github/workflows/supabase-deploy.yml` detecta mudança real no conteúdo de
  migrations, conecta ao projeto, executa `db push --dry-run` e então publica
  com `--skip-vault`. Publicações são serializadas e migrations antigas não
  são aplicadas novamente se os arquivos não mudarem.
- `.github/workflows/web-deploy-vercel.yml` compila Flutter Web em release e
  publica na Vercel quando arquivos do cliente mudam; exclui banco e Markdown.
  Depende de `VERCEL_TOKEN`, `VERCEL_ORG_ID` e `VERCEL_PROJECT_ID`, e assume
  que o `main` já passou pelos checks obrigatórios.
- O workflow de metadados confere igualdade entre cópias canônicas e arquivos
  espelhados de licença/citação.

### Lacunas de entrega e operação

- Há deploy automatizado do Web, mas não foram encontrados workflows de build
  ou publicação de APK/Windows. Essas entregas exigem um processo separado.
- O CI ainda compila e testa o worker Rust arquivado; assim, a referência
  obsoleta continua sendo um gate obrigatório de PR, embora não seja o backend
  ativo. A primeira execução paralela de `cargo test --locked` encontrou
  `STATUS_ACCESS_VIOLATION` no `rustc`; a repetição serializada
  (`cargo test --locked -j 1`) compilou e passou, mas não há testes Rust
  (`0 passed`).
- Os workflows de banco e Edge Functions publicam apenas `main`; para
  migrations, a prévia é explícita antes do push. O monitor de saúde e a
  publicação da função `health` já estão descritos como ativos no backend.

# MistakeMap — Decisões e Arquitetura do Backend

> Documento vivo. Atualizado em: 2026-09-30

---

## 1. Visão Geral da Arquitetura

```
Flutter (cliente móvel)
    │
    ├── Auth / RPC / DB queries ──► Supabase (PostgreSQL + Auth)
    │
    └── POST /upload-url ──────────► Supabase Edge Functions
    │   POST /process-batch             ├── upload-url   → gera presigned URL → R2
    │   GET  /health                    ├── process-batch → baixa R2 → OCR → LLM
    │                                   └── health        → verifica DB + R2
    │
    └── Upload de imagens ─────────► Cloudflare R2 (via presigned URL)
                                          ▲
                                          │ download para OCR/LLM
                                    pg_cron (Supabase, a cada N min)
                                    └── POST /process-batch ◄── pg_net
```

### Componentes e responsabilidades

| Componente | Plataforma | Função |
|---|---|---|
| **Flutter** | Mobile (Android/iOS) | Cliente — autenticação, upload, visualização |
| **Supabase** | Supabase Cloud (free tier) | Auth (JWT ES256), PostgreSQL, RLS, RPCs, Edge Functions |
| **Cloudflare R2** | Cloudflare (free tier) | Storage de imagens e assets dos alunos |
| **Edge Functions** | Supabase (Deno/TypeScript) | `upload-url`, `process-batch`, `health` — sem VM, sem custo fixo |

> **Nota histórica:** o backend foi originalmente implementado como um worker Rust
> rodando no Fly.io (ver `worker/`). Migrado para Supabase Edge Functions em
> 2026-09-28 para eliminar dependência de VM e manter tudo no free tier sem
> necessidade de cartão de crédito.

---

## 2. Decisões de Linguagem e Plataforma

### Por que Supabase Edge Functions e não VM (Fly.io / Cloud Run)?

| Critério | Edge Functions (Supabase) | Fly.io | Cloud Run |
|---|---|---|---|
| Custo fixo | **Zero** | Trial para após 5 min sem cartão | Grátis até 2M req/mês |
| Deploy | `supabase functions deploy` | `flyctl deploy` | `gcloud run deploy` |
| Secrets | `supabase secrets set` | `flyctl secrets set` | Secret Manager |
| Cold start | ~500ms (Deno) | Nenhum (VM quente) | ~1–3s |
| Acesso ao DB | Via `SUPABASE_DB_URL` direto | Via `DATABASE_URL` | Via `DATABASE_URL` |
| Auth JWT | Via `@supabase/supabase-js` | Via `jsonwebtoken` (Rust) | Idem |
| Linguagem | TypeScript / Deno | Rust | Rust / qualquer |
| Manutenção | Zero infra | Gerenciar VM e deploy | Gerenciar imagem e IAM |

**Decisão (2026-09-28): Supabase Edge Functions.** O pipeline é baseado em lote
(chamadas HTTP externas para OCR e LLM) — não há trabalho CPU-bound que
justifique uma VM. O cold start de ~500ms é aceitável para um job de cron.

> **Nota sobre o worker Rust:** o código em `worker/` continua no repositório como
> referência histórica e como fallback caso as Edge Functions se tornem
> insuficientes (ex: timeout de 150s do Deno vs 300s do Cloud Run). Para
> reativar, seguir as instruções da Seção 9 (Deploy histórico — Fly.io).

### Por que Cloudflare R2 e não Supabase Storage?

- R2 free tier: **10 GB storage + egress gratuito**
- Supabase Storage free tier: 1 GB storage + egress cobrado
- Flutter não pode guardar credenciais do R2 → padrão de presigned URL via Edge Function

---

## 3. Autenticação e JWT

### Algoritmo: ES256 (ECC P-256), não HS256

O Supabase migrou de HS256 (segredo simétrico compartilhado) para ES256 (par de chaves assimétricas ECC P-256). O worker valida JWTs com a **chave pública** obtida do JWKS endpoint — nunca precisa do segredo de assinatura.

- **JWKS URL**: `https://bmdjicshcjpknuaywaph.supabase.co/auth/v1/.well-known/jwks.json`
- **kid atual**: `a447eede-da03-4ef5-aed0-46c765a2eacb`
- A chave é buscada **uma única vez na inicialização** e armazenada como `Arc<DecodingKey>` no `AppState` — sem latência de rede no caminho crítico de cada requisição

### Variáveis de ambiente do worker

```env
DATABASE_URL                   # Supabase PostgreSQL connection string
SUPABASE_URL                   # https://bmdjicshcjpknuaywaph.supabase.co
CLOUDFLARE_ACCOUNT_ID          # 954f3233c7c998b8e862c1a59673d9a0
CLOUDFLARE_R2_S3_ENDPOINT      # https://954f3233c7c998b8e862c1a59673d9a0.r2.cloudflarestorage.com
CLOUDFLARE_R2_BUCKET           # mistakemap
CLOUDFLARE_R2_ACCESS_KEY_ID    # (R2 API token)
CLOUDFLARE_R2_SECRET_ACCESS_KEY# (R2 API token secret)
PORT                           # 8080 (padrão; a plataforma injeta automaticamente)
WORKER_CRON_SECRET             # segredo do header X-Cron-Secret em POST /process-batch
```

---

## 4. Fluxo de Upload (Flutter → R2)

O Flutter **nunca** guarda credenciais do R2. O padrão é:

```
Flutter                 Edge Function upload-url         Cloudflare R2
  │                              │                            │
  │── POST /upload-url ─────────►│                            │
  │   Authorization: Bearer JWT  │── valida sessão (/auth/v1/user)
  │   {filename, content_type,   │── assina PUT (15 min)      │
  │    size_bytes}               │── reserva cota R2          │
  │◄── {upload_url, object_path, │                            │
  │     content_type, expires_in}│                            │
  │── PUT upload_url (bytes, mesmo Content-Type) ────────────►│
  │                                                           │
  │── INSERT exercises / attempts(status='uploading') ──► Supabase (RLS)
  │── INSERT attempt_assets {object_path, sha256} ─────► Supabase (RLS)
  │── UPDATE attempts SET status='pending' ────────────► Supabase (trigger)
```

- Presigned URL expira em **15 minutos**; `Content-Type` e `Content-Length`
  fazem parte da assinatura, então o PUT repete o `content_type` devolvido
  (`image/jpeg`, nunca `image/jpg`) e exatamente `size_bytes` bytes
- Formatos aceitos: `jpg`/`jpeg` → `image/jpeg`, `png`, `webp`; até **8 MB**
- Caminho no R2: `uploads/{user_id}/{uuid}.{ext}`
- A política `attempt_assets_owner_insert` só aceita o anexo com a tentativa em
  `uploading`, caminho do próprio usuário e `sha256` com 64 caracteres
  hexadecimais; a análise confere esse hash antes de enviar a imagem à IA
- O trigger `guard_attempt_ai_state` só deixa o cliente criar tentativas em
  `uploading`/`pending` e mover `uploading → pending`; os demais estados são do
  servidor
- O Flutter envia a foto antes de gravar no banco e desfaz o exercício parcial
  se algo falhar (`TelaAdicionarExercicio._continuar`)

---

## 5. Pipeline de Processamento (Worker)

### Processamento em lote sob demanda

O worker **não tem mais loop próprio**. A cadência vem de fora: o `pg_cron` do
Supabase chama `POST /process-batch` via `pg_net`, e cada chamada processa um
lote e retorna. Isso permite o processo escalar a zero entre execuções — o que
viabiliza hospedagem gratuita sem VM ligada 24/7 (ver seção 9).

- Batch: **5 tentativas por chamada** (`pipeline::BATCH_SIZE`), pequeno para caber no timeout de requisição da plataforma
- Autorização: segredo compartilhado no header `X-Cron-Secret`, comparado em tempo constante
- Padrão: `FOR UPDATE SKIP LOCKED` — chamadas concorrentes nunca processam a mesma tentativa

### Máquina de estados de `attempts`

```
pending ──► queued ──► processing ──► awaiting_review ──► completed
                                  └──► retryable_failed ──► dead_letter
```

| Status | Quem transiciona | Significado |
|---|---|---|
| `uploading` | Flutter/RPC | Sessão criada, objeto ainda não confirmado |
| `pending` | RPC transacional | Objeto validado, job deve existir |
| `queued` | Worker (fetch_pending) | Adquirido atomicamente pelo worker |
| `processing` | Worker | Lease ativo, execução em andamento |
| `awaiting_review` | Worker | Eventos produzidos, revisão humana necessária |
| `completed` | Worker/RPC | Pipeline concluído |
| `retryable_failed` | Worker | Falha transitória, próxima tentativa agendada |
| `dead_letter` | Worker (após limite) | Limite de retry atingido |
| `cancelled` | RPC | Cancelado antes do processamento |

### Controle de concorrência otimista

Cada `UPDATE` de status usa `WHERE id = $1 AND version = $2` — se outra instância do worker já atualizou a linha, o `rows_affected` será 0 e o worker atual descarta a operação sem erro.

### Fases do pipeline (roadmap)

> A tabela e a máquina de estados acima descrevem o worker Rust. Nas Edge
> Functions (ativas), `process-batch` e `analyze-attempt` compartilham
> `_shared/ai_service.ts`: lease de 180 s em `processing_runs`, até 3 tentativas
> por `pipeline_version` e cota diária por usuário em `ai_daily_usage`.

| Fase | Status | Descrição |
|---|---|---|
| Download R2 | ✅ Implementado | `_shared/ai_service.ts::imageInputs` (confere SHA-256 e formato) |
| Transcrição + classificação | ✅ Implementado | Gemini multimodal (`_shared/gemini.ts`), saída em JSON Schema validada por `_shared/ai_contract.ts`; grava `attempt_analyses`, `corrections`, `concepts`, `error_events` e `mastery_events` |
| Exercícios direcionados | ✅ Implementado | `generate-practice` cria `practice_sets` e guarda o gabarito só no servidor (`practice_answer_keys`) |
| Exibir análise no Flutter | 🔲 Pendente | O app ainda não lê `attempt_analyses`/`error_events` nem chama `generate-practice` |
| Signed URLs (leitura) | 🔲 Pendente | Para Flutter visualizar assets salvos |

---

## 6. Controle de Cota R2 (95% de reserva técnica)

### Limites gratuitos do Cloudflare R2

| Tipo | Limite mensal | Teto (95%) |
|---|---|---|
| Class A (PUT/POST/LIST) | 1.000.000 ops | 950.000 ops |
| Class B (GET) | 10.000.000 ops | 9.500.000 ops |
| Storage | 10 GB | ~9,5 GB |
| Egress | ilimitado | — |

### Implementação (`worker/src/quota.rs`)

- Tabela `r2_quota_usage` no Supabase PostgreSQL — coluna `period CHAR(7)` formato `YYYY-MM`
- `check_class_a()` — chamado **antes** de gerar URL presigned; retorna `503` se estourado
- `check_class_b()` — chamado **antes** de cada download do lote
- `increment_class_a()` — chamado após gerar URL (proxy para o PUT futuro do Flutter)
- `increment_class_b()` — chamado após download bem-sucedido
- `add_storage_bytes()` — acumula bytes transferidos
- Erros de contagem são **logados mas não bloqueiam** a operação (fail-open nos contadores)

---

## 7. Estrutura do Banco de Dados (PostgreSQL — Supabase)

### Tabelas principais

| Tabela | Função |
|---|---|
| `subjects` | Disciplinas e domínios (Cálculo, Física, etc.) |
| `concepts` | Nós do grafo conceitual |
| `concept_edges` | Relações dirigidas entre conceitos |
| `error_taxonomy` | Categorias canônicas de erro (Sinal, Unidade, Lógica, etc.) |
| `attempts` | Agregado da submissão e estado do pipeline |
| `attempt_assets` | Metadados dos arquivos no R2 (object_path, sha256, etc.) |
| `processing_runs` | Execuções, leases e idempotência |
| `ocr_artifacts` | Saída OCR normalizada e auditável |
| `error_events` | Eventos finais / predições de erro do LLM |
| `audit_log` | Trilha append-only de mutações sensíveis |
| `r2_quota_usage` | Rastreamento mensal de operações R2 |
| `attempt_analyses` | Diagnóstico da IA por tentativa (JSON validado, modelo, `pipeline_version`) |
| `practice_sets` | Conjuntos de exercícios gerados pela IA a partir dos erros |
| `practice_answer_keys` | Gabaritos gerados — **sem acesso do cliente** |
| `ai_daily_usage` | Cota diária de análises e gerações por usuário |

### RLS (Row Level Security)

- Todas as tabelas com RLS habilitado
- `attempts`: `auth.uid() = user_id` — aluno só vê suas próprias tentativas
- `error_events`, `corrections`, `mastery_events`, `attempt_analyses`,
  `practice_sets`: somente leitura para o dono; escrita só pela `service_role`
- `processing_runs`, `practice_answer_keys` e `ai_daily_usage`: sem acesso ao cliente Flutter
- `r2_quota_usage`: leitura para usuários autenticados, escrita pela `service_role`
- `audit_log`: append-only, consulta apenas administrativa
- `profiles`: dono lê e edita o próprio perfil (sem alterar `role`); administrador
  lê e atualiza qualquer perfil via `public.is_admin()` (`SECURITY DEFINER`, evita
  recursão de RLS — migração `20260929112200`)

---

## 8. Estrutura das Edge Functions

```
supabase/functions/
├── _shared/
│   ├── ai_contract.ts   # JSON Schemas, validação da saída da IA, PublicError
│   ├── ai_http.ts       # CORS, corpo limitado, autenticação, segredo do cron
│   ├── ai_service.ts    # análise (claim/lease/cota), leitura da R2, geração de exercícios
│   └── gemini.ts        # cliente generateContent (JSON Schema, imagens inline)
├── analyze-attempt/     # POST {attempt_id} → analisa ou devolve o diagnóstico em cache
├── generate-practice/   # POST {subject_id, count 3–5} → exercícios direcionados
├── process-batch/       # POST (X-Cron-Secret) → analisa a fila de tentativas pendentes
├── upload-url/          # POST → valida sessão, assina PUT na R2, reserva cota
│   └── handler.ts       # regras puras e testáveis do contrato de upload
├── health/              # GET → verifica DB (SELECT 1) e R2 (HEAD bucket)
├── tests/               # deno test (contrato da IA, CORS e upload-url)
├── deno.json            # import map usado por `deno check`/`deno test` (mesmas versões das funções)
└── deno.lock
supabase/config.toml     # verify_jwt de cada função, lido pelo deploy
```

Cada função tem `index.ts` (entrypoint), `handler.ts` (lógica) e `deno.json`
(imports `npm:`, iguais aos da raiz). Testes locais, os mesmos do CI:

```bash
cd supabase/functions
deno check --frozen */index.ts
deno test --frozen --allow-env
```

### Endpoints

| Método | Função | `verify_jwt` | Autenticação |
|---|---|---|---|
| `POST` | `/upload-url` | `false` | Bearer JWT validado pela própria função |
| `POST` | `/analyze-attempt` | `false` | Bearer JWT validado pela própria função |
| `POST` | `/generate-practice` | `false` | Bearer JWT validado pela própria função |
| `POST` | `/process-batch` | `false` | Header `x-cron-secret` (pg_cron) |
| `GET` | `/health` | `false` | Pública (monitor) |

Base: `https://bmdjicshcjpknuaywaph.supabase.co/functions/v1/`

O `verify_jwt` fica em `supabase/config.toml`. As funções de IA usam `false`
para responder ao preflight `OPTIONS` do navegador; o `POST` só segue depois
que `authenticate()` valida o JWT em `/auth/v1/user`. Sem entrada no
`config.toml`, o deploy liga o `verify_jwt` e o pg_cron passa a receber 401.

### IA: Google Gemini (camada gratuita)

`gemini.ts` chama `generateContent` com saída em JSON Schema
(`generationConfig.responseFormat`), `thinkingLevel` `LOW` e a chave no
cabeçalho `x-goog-api-key`, nunca na URL. O legado `responseSchema` recusava
`additionalProperties` e `["boolean","null"]` com HTTP 400. Erros 5xx do
provedor são repetidos no modelo reserva (`GEMINI_FALLBACK_MODEL`), dentro de
um prazo total que respeita o limite de 150 s das Edge Functions. O modelo
realmente usado é gravado em `attempt_analyses.model` e `practice_sets.model`.
A saída é validada de novo em `ai_contract.ts`, porque o Gemini ignora
`minLength`/`maxLength`.

> **Privacidade:** na camada gratuita, o Google pode usar prompts, respostas e
> imagens para melhorar seus produtos, com revisão humana, e os termos pedem
> para não enviar dados pessoais. Fotos de provas com nome ou matrícula devem
> ser recortadas, ou deve-se usar a camada paga.

### CORS das funções de IA

Origens de loopback (`http://localhost:<porta>`, `http://127.0.0.1:<porta>`)
são sempre aceitas, porque o `flutter run -d chrome` usa uma porta aleatória.
Front-ends publicados precisam estar em `ALLOWED_ORIGINS`, separados por
vírgula. Origem recusada não recebe `Access-Control-Allow-Origin`. CORS não
substitui autenticação: todo handler valida o JWT.

### Body de requisição do `upload-url`

```json
{ "filename": "exercicio.jpg", "content_type": "image/jpeg", "size_bytes": 482133 }
```

Resposta `200`: `{ "upload_url", "object_path", "content_type", "expires_in": 900 }`.
Erros: `400 invalid_upload`, `401 unauthorized`, `429 storage_quota_exceeded`,
`503 upload_unavailable`.

### Secrets necessários (configurar via `supabase secrets set`)

```
SUPABASE_DB_URL                 # string de conexão direta (porta 5432, session mode)
CLOUDFLARE_R2_S3_ENDPOINT       # https://954f3233c7c998b8e862c1a59673d9a0.r2.cloudflarestorage.com
CLOUDFLARE_R2_BUCKET            # mistakemap
CLOUDFLARE_R2_ACCESS_KEY_ID     # (R2 API token)
CLOUDFLARE_R2_SECRET_ACCESS_KEY # (R2 API token secret)
WORKER_CRON_SECRET              # segredo compartilhado para X-Cron-Secret (≥ 24 caracteres)
GEMINI_API_KEY                  # chave do Google AI Studio (nunca no cliente)
GEMINI_MODEL                    # opcional; padrão gemini-flash-latest
GEMINI_FALLBACK_MODEL           # opcional; padrão gemini-3.6-flash (usado após erro 5xx)
AI_ANALYSES_PER_DAY             # opcional; 1–50 (padrão 50)
AI_PRACTICE_PER_DAY             # opcional; 1–10 (padrão 10)
ALLOWED_ORIGINS                 # opcional; origens web publicadas (loopback é sempre aceito)
```

> `SUPABASE_URL` e `SUPABASE_ANON_KEY` são injetados automaticamente pelo runtime
> do Supabase — não precisam ser configurados manualmente.

### Referência histórica — Worker Rust (arquivado)

O código em `worker/` (Rust/axum/SQLx) implementa o mesmo contrato de API.
Mantido como referência e fallback para o caso de as Edge Functions se tornarem
insuficientes (timeout Deno 150s vs Cloud Run 300s por requisição).

```
worker/
├── Cargo.toml          # axum, sqlx, aws-sdk-s3, jsonwebtoken, reqwest, chrono, tokio
├── fly.toml            # configuração Fly.io (plataforma anterior)
└── src/
    ├── main.rs / config.rs / db.rs / storage.rs
    ├── attempts.rs / pipeline.rs / quota.rs
    └── routes/{health,process_batch,upload_url}.rs
```

---

## 9. Deploy — Supabase Edge Functions (ativo desde 2026-09-28)

### CI/CD (GitHub Actions, desde 2026-09-30)

| Workflow | Quando roda | O que faz |
|---|---|---|
| `ci.yml` | push no `main` e todo pull request (exceto só `.md`) | `deno check` + `deno test` nas funções; `flutter analyze`, `dart format`, `flutter test`; `cargo check`, `clippy -D warnings`, `cargo test` no worker |
| `supabase-functions-deploy.yml` | push no `main` que altera `supabase/functions/**` ou `supabase/config.toml` | repete os testes Deno e, se passarem, publica todas as funções com `supabase functions deploy --use-api` |
| `supabase-deploy.yml` | push no `main` que altera migrations | `supabase db push` (com dry-run antes) a partir de `appmistakemap/database` |

Os workflows usam os secrets do GitHub `SUPABASE_ACCESS_TOKEN`,
`SUPABASE_PROJECT_ID` e `SUPABASE_DB_PASSWORD`. As chaves de runtime (Gemini,
R2) ficam só nos secrets do Supabase. Com o CD, nada precisa ser publicado à
mão: basta fazer merge no `main`.

### Comandos manuais (fallback)

```bash
# Todas as funções; o verify_jwt de cada uma vem de supabase/config.toml.
# --use-api empacota no servidor do Supabase, sem Docker.
supabase functions deploy --project-ref bmdjicshcjpknuaywaph --use-api

# Configurar secrets (uma vez; não ficam no repositório)
supabase secrets set --project-ref bmdjicshcjpknuaywaph \
  SUPABASE_DB_URL="postgresql://postgres.<ref>:<senha>@aws-0-sa-east-1.pooler.supabase.com:5432/postgres" \
  CLOUDFLARE_R2_S3_ENDPOINT="https://954f3233c7c998b8e862c1a59673d9a0.r2.cloudflarestorage.com" \
  CLOUDFLARE_R2_BUCKET="mistakemap" \
  CLOUDFLARE_R2_ACCESS_KEY_ID="..." \
  CLOUDFLARE_R2_SECRET_ACCESS_KEY="..." \
  WORKER_CRON_SECRET="..."

# Ver logs em tempo real
supabase functions logs health        --project-ref bmdjicshcjpknuaywaph
supabase functions logs process-batch --project-ref bmdjicshcjpknuaywaph
```

### Conexão com o Postgres: session mode (porta 5432)

As Edge Functions se conectam via `postgresjs` com `prepare: false` (obrigatório
com Supavisor/pgBouncer). Usar porta **5432** (session mode), não 6543 (transaction
mode) — o `FOR UPDATE SKIP LOCKED` requer que a mesma conexão mantenha o estado
da transação.

### Configuração do pg_cron (aplicar no SQL Editor do Supabase)

> **Estado em 30/09/2026:** o projeto já tem o job `process-batch-every-minute`
> (`* * * * *`), criado manualmente fora das migrações. Ele guarda o valor do
> `x-cron-secret` em texto puro no comando do `cron.job`. Recomenda-se recriá-lo
> lendo o segredo do Supabase Vault (`vault.decrypted_secrets`) e rotacionar
> `WORKER_CRON_SECRET`. O modelo abaixo é a referência original.

```sql
-- Configuração separada: a migration de monitoramento abaixo não cria este job.
-- Chamar process-batch a cada N minutos (ex: a cada 1 min para MVP)
SELECT cron.schedule(
  'process-batch-trigger',
  '* * * * *',
  format(
    $$SELECT net.http_post(
        url    := 'https://bmdjicshcjpknuaywaph.supabase.co/functions/v1/process-batch',
        headers := jsonb_build_object('x-cron-secret', %L),
        body   := '{}'::jsonb,
        timeout_milliseconds := 25000
    )$$,
    current_setting('app.worker_cron_secret')
  )
);
```

> Antes de executar: `ALTER DATABASE postgres SET app.worker_cron_secret = '<valor>';`

### Monitor de saúde (migration `20260928120000`, aplicada)

O job `worker-health-monitor` agenda `GET /functions/v1/health` a cada 5 min,
com histórico em `net._http_response`. A migração já consta do histórico remoto
e agora está no diretório canônico.

Até 30/09/2026 a função `health` não estava implantada, e o job recebia 404 a
cada execução. Ela passa a ser publicada pelo CD com `verify_jwt = false`
(`supabase/config.toml`), já que o pg_cron não envia JWT. Consulte
[o procedimento de migrações](appmistakemap/database/README.md).

---

## 10. Deploy histórico — Worker Rust no Fly.io (arquivado)

> O Fly.io não tem mais plano gratuito: trial dá ~2h de VM no total e desliga
> cada máquina após 5 minutos sem cartão. Esse path foi abandonado em favor
> das Edge Functions.

O código em `worker/` e o `fly.toml` permanecem no repositório como referência.
Se precisar reativar (ex: timeout Deno 150s for insuficiente para OCR pesado):

```bash
cd worker
flyctl deploy
flyctl secrets set DATABASE_URL="..." WORKER_CRON_SECRET="..." # etc.
```

Armadilhas documentadas do primeiro deploy estão preservadas no histórico git
(último commit que tocou o BACKEND.md antes de 2026-09-28).

---

## 10. Dados de Teste

### Bucket R2 `mistakemap`

- **9 imagens PNG** de caderno matemático geradas por `scripts/seed_r2_test_data.ps1`
- 2 usuários fictícios × 3 tentativas × 1-2 assets cada
- `user-aluno-alpha-0001`: Derivada Parcial, Limite 0/0, Integral por Partes
- `user-aluno-beta-0002`: Circuito RC, Lei de Kirchhoff, Vetor Posição

### Credenciais de desenvolvimento

- Todas as credenciais ficam **exclusivamente** em `worker/.env` (gitignored)
- Nunca commitadas no repositório

---

## 11. Pendências e Próximos Passos

- [x] Criar `Dockerfile` multi-stage para o worker Rust
- [x] Criar `fly.toml` e fazer primeiro deploy no Fly.io
- [x] Transcrição e classificação de erros por IA (Gemini multimodal nas Edge Functions)
- [x] Taxonomia base de `error_types` (7 categorias, migração `20260929052429`)
- [x] Client Flutter: auth, telas, upload com SHA-256 no contrato da `upload-url`
- [x] Versionar no repositório as migrações e Edge Functions aplicadas em produção (30/09/2026)
- [ ] Exibir no Flutter o diagnóstico (`attempt_analyses`, `error_events`) e chamar `generate-practice`
- [x] CI/CD no GitHub Actions: `ci.yml` e `supabase-functions-deploy.yml`, que também publica a `health` (30/09/2026)
- [ ] Mover o `x-cron-secret` do job `process-batch-every-minute` para o Vault e rotacioná-lo
- [ ] Rate limit das escritas do servidor: os triggers `enforce_rate_limit` usam
      `auth.uid()`, que é NULL na conexão das Edge Functions. Todas as análises
      dividem o balde `user:anon` (300 inserts/min), e cada análise faz até ~42
      inserts. Criar uma migration que isente o role do servidor ou aplique o
      limite pelo `user_id`.
- [ ] Reservar a cota diária só depois das validações locais (texto, imagens),
      para que erros determinísticos não consumam análises do aluno
- [ ] Remover da R2 os objetos de tentativas excluídas (hoje ficam órfãos)
- [ ] Criar signed URLs para leitura de assets pelo Flutter
- [ ] Implementar cálculo de prioridade: `F×R×I×(1-M)` como função PostgreSQL
- [ ] Autorizar MCPs Cloudflare no terminal interativo (`/mcp` em sessão `claude`)

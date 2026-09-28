# MistakeMap — Decisões e Arquitetura do Backend

> Documento vivo. Atualizado em: 2026-09-28

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

### Por que Cloudflare R2 e não Supabase Storage?

- R2 free tier: **10 GB storage + egress gratuito**
- Supabase Storage free tier: 1 GB storage + egress cobrado
- Flutter não pode guardar credenciais do R2 → padrão de presigned URL via worker

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
Flutter                    Worker (Fly.io)              Cloudflare R2
  │                              │                            │
  │── POST /upload-url ─────────►│                            │
  │   Authorization: Bearer JWT  │                            │
  │                              │── valida JWT ES256         │
  │                              │── verifica cota R2 (95%)   │
  │                              │── gera presigned PUT URL ──►│
  │◄── { url, object_path } ─────│                            │
  │                              │                            │
  │── PUT {url} com bytes ───────────────────────────────────►│
  │                              │                            │
  │── RPC finalizar_tentativa ──►│ (via Supabase, salva       │
  │   { attempt_id, object_path }│  object_path em attempt_   │
  │                              │  assets)                   │
```

- Presigned URL expira em **15 minutos**
- Extensões permitidas: `jpg`, `jpeg`, `png`, `webp`, `pdf`
- Caminho no R2: `uploads/{user_id}/{uuid}.{ext}`
- ⚠️ A RPC `finalizar_tentativa` do diagrama **ainda não existe** — hoje nada cria linhas em `attempt_assets` nem move `attempts` para `pending`

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

| Fase | Status | Descrição |
|---|---|---|
| Download R2 | ✅ Implementado | `storage::download_asset` via aws-sdk-s3 |
| OCR matemático | 🔲 P1 (TODO) | `ocr.rs` — TODO em `pipeline.rs::process_attempt` |
| LLM classificação | 🔲 P1 (TODO) | `llm.rs` — classificar erros, gravar `error_events` |
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

### RLS (Row Level Security)

- Todas as tabelas com RLS habilitado
- `attempts`: `auth.uid() = student_id` — aluno só vê suas próprias tentativas
- `error_events`: INSERT/UPDATE apenas pela `service_role` (worker)
- `processing_runs` e `r2_quota_usage`: sem acesso ao cliente Flutter
- `audit_log`: append-only, consulta apenas administrativa

---

## 8. Estrutura das Edge Functions

```
supabase/functions/
├── health/
│   ├── deno.json        # imports: aws4fetch, postgresjs
│   └── index.ts         # GET → verifica DB (SELECT 1) e R2 (HEAD bucket) em paralelo
├── upload-url/
│   ├── deno.json        # imports: @supabase/supabase-js, aws4fetch, postgresjs
│   └── index.ts         # POST → valida JWT Supabase, verifica cota, gera presigned URL
└── process-batch/
    ├── deno.json        # imports: aws4fetch, postgresjs
    └── index.ts         # POST → X-Cron-Secret, busca pending, baixa R2, TODO OCR→LLM
```

### Endpoints

| Método | Função | URL |
|---|---|---|
| `GET` | `/health` | `https://bmdjicshcjpknuaywaph.supabase.co/functions/v1/health` |
| `POST` | `/upload-url` | `https://bmdjicshcjpknuaywaph.supabase.co/functions/v1/upload-url` |
| `POST` | `/process-batch` | `https://bmdjicshcjpknuaywaph.supabase.co/functions/v1/process-batch` |

### Body de requisição do `upload-url`

```json
{ "filename": "foto.jpg", "content_type": "image/jpeg" }
```

**Autenticação:** `Authorization: Bearer <supabase-jwt>` (token do usuário autenticado).

### Secrets necessários (configurar via `supabase secrets set`)

```
SUPABASE_DB_URL                 # string de conexão direta (porta 5432, session mode)
CLOUDFLARE_R2_S3_ENDPOINT       # https://954f3233c7c998b8e862c1a59673d9a0.r2.cloudflarestorage.com
CLOUDFLARE_R2_BUCKET            # mistakemap
CLOUDFLARE_R2_ACCESS_KEY_ID     # (R2 API token)
CLOUDFLARE_R2_SECRET_ACCESS_KEY # (R2 API token secret)
WORKER_CRON_SECRET              # segredo compartilhado para X-Cron-Secret
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

### Comandos

```bash
# Deployar todas as funções de uma vez
supabase functions deploy --project-ref bmdjicshcjpknuaywaph

# Ou individualmente
supabase functions deploy health        --project-ref bmdjicshcjpknuaywaph
supabase functions deploy upload-url    --project-ref bmdjicshcjpknuaywaph
supabase functions deploy process-batch --project-ref bmdjicshcjpknuaywaph

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

```sql
-- Já incluído na migration supabase/migrations/20260928120000_worker_keepalive_cron.sql
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

### Monitor de saúde (migration já criada)

O job `worker-health-monitor` (migration `20260928120000`) pinga
`GET /functions/v1/health` a cada 5 min. Histórico em `net._http_response`.

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
- [ ] Implementar `ocr.rs` (Fase P1) — integração com API de OCR matemático
- [ ] Implementar `llm.rs` (Fase P1) — classificação de erros via LLM
- [ ] Criar signed URLs para leitura de assets pelo Flutter
- [ ] Implementar `seed.sql` com taxonomia real (`error_types`, `subjects`)
- [ ] Implementar cálculo de prioridade: `F×R×I×(1-M)` como função PostgreSQL
- [ ] Autorizar MCPs Cloudflare no terminal interativo (`/mcp` em sessão `claude`)
- [ ] Iniciar client Flutter (auth, screens, upload flow, visualização)

# MistakeMap — Decisões e Arquitetura do Backend

> Documento vivo. Atualizado em: 2026-09-16

---

## 1. Visão Geral da Arquitetura

```
Flutter (cliente móvel)
    │
    ├── Auth / RPC / DB queries ──► Supabase (PostgreSQL + Auth)
    │
    └── Upload de imagens ─────────► Cloudflare R2 (via presigned URL)
                                          ▲
                                          │ download para OCR/LLM
                                    Rust Worker (Fly.io → Cloud Run)
                                          ▲
                                          └── POST /process-batch ◄── pg_cron (Supabase)
```

### Componentes e responsabilidades

| Componente | Plataforma | Função |
|---|---|---|
| **Flutter** | Mobile (Android/iOS) | Cliente — autenticação, upload, visualização |
| **Supabase** | Supabase Cloud (free tier) | Auth (JWT ES256), PostgreSQL, RLS, RPCs |
| **Cloudflare R2** | Cloudflare (free tier) | Storage de imagens e assets dos alunos |
| **Rust Worker** | Fly.io (trial — ver seção 9) | Pipeline em lote sob demanda: lote → OCR → LLM → gravar resultados |

---

## 2. Decisões de Linguagem e Plataforma

### Por que Rust para o worker?

- Worker já ~60% implementado em Rust (axum, SQLx, tokio, aws-sdk-s3)
- Baixo consumo de memória (~15-30 MB RSS) — cabe folgado numa VM `shared-cpu-1x` de 256 MB
- `FOR UPDATE SKIP LOCKED` e controle de concorrência otimista são triviais com SQLx async
- OCR e LLM são chamadas HTTP para APIs externas — sem vantagem do Python nesse ponto
- **Decisão: manter Rust. Não migrar para Python ou C++**

### Por que Fly.io e não Railway ou Render?

| Critério | Fly.io | Railway | Render |
|---|---|---|---|
| Plano sem cartão | Trial: **máquina para após 5 min** | 500h/mês (~21 dias) | 750h/mês + spin-down |
| Poll loop 24/7 | ⚠️ Exige cartão | ❌ Para antes do fim do mês | ❌ Cold start de 50s |
| Ping artificial | — | Proibido pelos termos | Proibido pelos termos |
| Cold start | Nenhum (com cartão) | Nenhum (enquanto tem horas) | ~50s após inatividade |

**Decisão: Fly.io**, com uma ressalva importante descoberta no deploy (ver seção 9).

> ⚠️ **Correção de uma premissa anterior.** Este documento afirmava que o Fly.io
> oferecia "3 VMs sempre ativas" no plano gratuito. Isso descreve o free tier
> antigo, que **não existe mais para contas novas**. Hoje uma conta sem cartão
> fica em trial, e o próprio runner do Fly desliga a máquina após 5 minutos:
> `Trial machine stopping. To run for longer than 5m0s, add a credit card`.

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

## 8. Estrutura do Worker Rust

```
worker/
├── Cargo.toml          # axum, sqlx, aws-sdk-s3, jsonwebtoken, reqwest, chrono, tokio
├── src/
│   ├── main.rs         # AppState, fetch_jwks, rotas e servidor HTTP
│   ├── config.rs       # Config lida de variáveis de ambiente
│   ├── db.rs           # connect() e ping() ao PostgreSQL
│   ├── storage.rs      # build_client(), ping(), download_asset()
│   ├── attempts.rs     # fetch_pending(), fetch_assets(), mark_completed(), mark_failed()
│   ├── pipeline.rs     # run_batch(): processa um lote de tentativas pendentes
│   ├── quota.rs        # check/increment Class A e B, add_storage_bytes
│   └── routes/
│       ├── mod.rs
│       ├── health.rs   # GET /health — verifica Postgres + R2
│       ├── process_batch.rs # POST /process-batch — acionado pelo pg_cron
│       └── upload_url.rs # POST /upload-url — valida JWT, verifica cota, gera presigned URL
```

### Endpoints HTTP

| Método | Rota | Função |
|---|---|---|
| GET | `/health` | Verifica conectividade com Postgres e R2 |
| POST | `/upload-url` | Gera presigned PUT URL para upload direto ao R2 |
| POST | `/process-batch` | Processa um lote de tentativas pendentes (exige `X-Cron-Secret`) |

---

## 9. Deploy (2026-09-15)

> ⚠️ **Migração em andamento: Fly.io → Google Cloud Run + pg_cron.**
> O Fly.io não tem mais plano gratuito: o trial dá **2 horas de VM no total ou
> 7 dias**, o que vier primeiro, e desliga cada máquina após 5 minutos. Um
> worker com poll loop 24/7 não cabe nisso.
>
> Decisão (2026-09-15): mover para o **Cloud Run**, cujo free tier não expira
> (2M requisições, 360.000 GB-s e 180.000 vCPU-s por mês), usando a mesma imagem
> Docker. Para isso o poll loop virou `POST /process-batch`, acionado pelo
> `pg_cron` + `pg_net` (já instalados no Supabase). Estimativa para cron a cada
> minuto, ~2 s por lote a 256 MB: ~21.600 GB-s e ~86.400 vCPU-s por mês.
>
> **Estado:** código pronto e testado localmente. Falta criar a conta GCP,
> fazer o deploy no Cloud Run e criar o job no `pg_cron`. A instância na Fly
> abaixo ainda roda a imagem **antiga** (com poll loop) — não fazer
> `flyctl deploy` desta versão sem antes configurar `WORKER_CRON_SECRET`, ou o
> worker não sobe.

### Estado atual

| Item | Valor |
|---|---|
| Plataforma | Fly.io |
| App | `mistakemap-worker` |
| URL | https://mistakemap-worker.fly.dev |
| Região | `gru` (São Paulo) |
| Máquinas | 1 × `shared-cpu-1x` |
| Imagem final | 36 MB |
| Health check | `GET /health` → `{"bucket":"mistakemap","database":"ok","r2":"ok"}` |

### Decisões de infraestrutura

- **1 máquina, não 2.** O Fly cria uma segunda máquina para HA por padrão. Fixado com `min_machines_running = 0` no `fly.toml` — o poll loop não perde trabalho num restart, porque as tentativas continuam na fila e o `FOR UPDATE SKIP LOCKED` impede processamento duplicado.
- **`auto_stop_machines = 'off'`** — obrigatório. O poll loop precisa rodar 24/7; se a máquina suspender, o pipeline para.
- **Secrets via `flyctl secrets set`** — nunca em arquivo versionado. As 7 variáveis do `Config::from_env()` estão configuradas.

### Armadilhas encontradas no primeiro deploy

Cada uma quebrou o build ou quebraria o runtime:

| Problema | Causa | Correção |
|---|---|---|
| `feature edition2024 is required` | `rust:1.82` não suporta `edition = "2024"` | Usar imagem Rust atual |
| `rustc 1.86 is not supported` | `aws-sdk-s3 1.145` e `sqlx 0.9` exigem rustc 1.94.1+ | `rust:slim-trixie` (stable atual) |
| Contexto de build de 3,8 GB | `target/` enviado a cada deploy | `.dockerignore` |
| `openssl-sys` não acha OpenSSL | `rust:slim` não traz `pkg-config`/`libssl-dev` | Instalar no estágio **builder** |
| `set DATABASE_URL to use query macros` | `quota.rs` usava `sqlx::query!` (validação em tempo de compilação) | Converter para a API runtime, como em `attempts.rs` |
| **glibc incompatível (silencioso)** | builder em `rust:slim` (**trixie**, glibc 2.41) e runtime em `debian:bookworm-slim` (glibc 2.36) | Ambos os estágios em **trixie** |
| libssl ausente no runtime | `openssl-sys` linka dinamicamente; runtime só tinha `ca-certificates` | Instalar `openssl` no runtime (o apt resolve a libssl correta) |

> A incompatibilidade de glibc é a mais perigosa: o build passa normalmente e o container só quebra ao subir. Num build multi-stage, **builder e runtime devem usar a mesma release do Debian**.

### Conexão com o Postgres: session mode, não transaction mode

```
postgresql://postgres.<ref>:<senha>@aws-0-sa-east-1.pooler.supabase.com:5432/postgres
```

Porta **5432** (session mode), não 6543 (transaction mode). O Supavisor em transaction mode multiplexa conexões por transação e quebra o cache de prepared statements do sqlx. O worker é um processo persistente com pool — precisa de session mode.

### Comandos

```
flyctl deploy              # build + deploy
flyctl status              # estado das máquinas
flyctl logs                # logs em tempo real
flyctl secrets list        # secrets (apenas nomes e digests)
```

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

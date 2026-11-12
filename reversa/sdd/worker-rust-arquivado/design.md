# Worker Rust arquivado — Design Técnico

## Interface

| Símbolo/rota | Entrada | Retorno | Observação |
|---|---|---|---|
| `GET /health` | Requisição HTTP | Status operacional | Não comprova pipeline de IA. 🟢 |
| `POST /upload-url` | JWT e solicitação de upload | URL/atributos de upload | Valida JWT e quota; contrato histórico aceita PDF. 🟢 |
| `POST /process-batch` | Header de segredo de cron | Resumo do lote | Protegido por segredo e processa batch limitado. 🟢 |
| `run_batch` | Pool PostgreSQL, cliente S3 e configuração | `BatchSummary` | Até cinco tentativas `pending`. 🟢 |
| `fetch_pending` | Pool e limite | Linhas de tentativa | Lock `FOR UPDATE SKIP LOCKED`; seleção atual não inclui `retryable_failed`. 🟢 |

Payloads HTTP detalhados devem ser lidos nos handlers Rust; não inferir contrato do worker a partir dos endpoints Edge ativos. 🟡

## Fluxo Principal

1. `main` carrega configuração obrigatória do ambiente, conecta Postgres/R2 e carrega chave de validação JWKS. 🟢 (`worker/src/main.rs`, `worker/src/config.rs`)
2. Rotas expõem health, URL assinada e processamento de lote. 🟢 (`worker/src/routes/`)
3. `upload_url` valida JWT e reserva cota, emitindo autorização de upload. 🟢
4. `run_batch` busca até cinco tentativas `pending` com locking concorrente. 🟢
5. Pipeline baixa assets do R2 e contabiliza uso. 🟢 (`worker/src/pipeline.rs`, `worker/src/storage.rs`)
6. OCR, persistência de artefatos e chamada LLM continuam como TODO; código marca tentativa `completed` depois do download. 🟢

## Fluxos Alternativos

- **JWT inválido:** rejeitar upload. 🟢
- **Segredo de cron inválido:** rejeitar batch. 🟢
- **Quota R2 excedida:** impedir emissão/uso de upload conforme erro. 🟢
- **Falha de processamento:** grava `retryable_failed`, mas busca posterior seleciona apenas `pending`. 🟢
- **PDF:** formato aceito no endpoint legado não corresponde aos formatos do backend ativo. 🟢

## Dependências

- Axum/Tokio para HTTP/concorrência. 🟢
- SQLx/PostgreSQL para estado e lock de tentativas. 🟢
- AWS SDK S3 para Cloudflare R2. 🟢
- `jsonwebtoken`/JWKS Supabase para autenticação. 🟢
- Gemini/OCR: não implementados neste worker. 🟢

## Decisões de Design Identificadas

| Decisão | Evidência no código | Confiança |
|---|---|---|
| Batch limitado com `SKIP LOCKED` | `worker/src/attempts.rs`, `worker/src/pipeline.rs` | 🟢 |
| JWT validado por JWKS e cron por segredo compartilhado | `worker/src/main.rs`, `worker/src/routes/process_batch.rs` | 🟢 |
| Cotas R2 controlam operações de upload/armazenamento | `worker/src/quota.rs`, `worker/src/routes/upload_url.rs` | 🟢 |
| Worker permanece arquivado após migração para Edge Functions | `BACKEND.md` | 🟢 |

## Estado Interno

Configuração contém conexão Postgres, credenciais R2, URL Supabase, segredo de cron e porta padrão 8080. Tentativas carregam ID, status e versão; resumo contém encontradas/concluídas/falhas. 🟢

## Observabilidade

`/health` e resumo do lote expõem estado operacional; testes Rust não foram localizados. O CI executa check/clippy/test, mas a execução prévia de `cargo test` passou com zero testes. 🟢

## Riscos e Lacunas

- 🔴 Não reativar: worker marca concluída sem OCR/LLM.
- 🔴 Retry declarado não é alcançado pela consulta de tentativas.
- 🟡 Upload PDF diverge do contrato atual JPEG/PNG/WebP.
- 🟢 Edge Functions continuam sendo fonte operacional ativa.

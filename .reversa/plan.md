# Plano de Exploração — MistakeMap
> Este arquivo é editável. O Reversa usa como guia, não como mandato.
> Agentes instalados: 63 · Estado: revisão aguardando respostas · Última atualização: 2026-10-31

## Fases de Discovery

- [x] **Scout** — Mapear estrutura de pastas, frameworks, dependências e pontos de entrada
  - `appmistakemap/lib/` (Flutter/Dart)
  - `archive/worker/src/` (Rust — Tokio/Axum/SQLx)
  - `appmistakemap/database/` (Supabase migrations)
  - Detectar integrações: Supabase Auth, Cloudflare R2, Edge Functions

- [x] **Archaeologist** — Análise de autenticação e navegação Flutter (`appmistakemap/lib/main.dart`, `appmistakemap/lib/auth/`, `appmistakemap/lib/layout/`)
- [x] **Archaeologist** — Análise de exercícios, IA, mapa de erros e prática (`appmistakemap/lib/ai/`)
- [x] **Archaeologist** — Análise do caderno local e sincronização offline (`appmistakemap/lib/local/`, `appmistakemap/lib/sync/`)
- [x] **Archaeologist** — Análise de administração, métricas e apresentação (`appmistakemap/lib/admin/`, `appmistakemap/lib/theme/`, `appmistakemap/lib/about/`)
- [x] **Archaeologist** — Análise das Edge Functions, contratos de IA e testes (`supabase/functions/`)
- [x] **Archaeologist** — Análise do schema, migrations e políticas PostgreSQL/RLS (`appmistakemap/database/supabase/`)
- [x] **Archaeologist** — Análise do worker Rust arquivado e limites de reativação (`archive/worker/src/`)
- [x] **Archaeologist** — Análise de CI/CD e deploy Web (`.github/workflows/`)

- [x] **Detective** — Extrair conhecimento de negócio implícito
  - Fórmula de prioridade: `P = F × R × I × (1 − M)`
  - Fluxo de validação pelo estudante (aceitar/rejeitar classificação)
  - Regras de classificação de erros (taxonomia)
  - Políticas de RLS no Supabase (por tabela)
  - Contratos de API do worker Rust (POST /process-batch, callbacks)

- [x] **Architect** — Síntese
  - Diagramas C4: Context, Container, Component
  - ERD completo das tabelas do Supabase (schema reconciliado 2026-09-10)
  - Mapa de integração Flutter ↔ Supabase ↔ R2 ↔ Worker
  - Diagrama de sequência: submissão → OCR → LLM → validação → mapa

- [x] **Writer** — Geração de especificações operacionais em `_reversa_sdd/`

- [x] **Reviewer** — Revisão das oito units concluída; quatro perguntas críticas aguardam resposta em `_reversa_sdd/questions.md`

## Prioridades

- [x] Documentar o pipeline de processamento (OCR → LLM → validação → mapa)
- [ ] Especificar os contratos de API do worker Rust (endpoints, payloads, erros)
- [ ] Documentar o schema do Supabase (reconciliado em 2026-09-10)
- [ ] Extrair as regras de RLS aplicadas por tabela
- [x] Mapear as Edge Functions do Supabase e seus gatilhos

## Após o Discovery — Próximos Fluxos Sugeridos

Quando o SDD estiver em `_reversa_sdd/`:

1. **`/reversa-docs`** — Gerar mini-site de documentação para a apresentação do trabalho
2. **`/reversa-forward`** — Implementar features pendentes com pipeline completo
3. **`/reversa-refactor`** — Identificar oportunidades de melhoria por ROI
4. **`/reversa-pricing-estimate`** — Estimar esforço restante até o MVP final

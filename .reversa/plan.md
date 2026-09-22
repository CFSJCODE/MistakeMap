# Plano de Exploração — MistakeMap
> Este arquivo é editável. O Reversa usa como guia, não como mandato.
> Agentes instalados: 63 · Estado: ready · Última atualização: 2026-09-22

## Fases de Discovery

- [ ] **Scout** — Mapear estrutura de pastas, frameworks, dependências e pontos de entrada
  - `appmistakemap/lib/` (Flutter/Dart)
  - `worker/src/` (Rust — Tokio/Axum/SQLx)
  - `appmistakemap/database/` (Supabase migrations)
  - Detectar integrações: Supabase Auth, Cloudflare R2, Edge Functions

- [ ] **Archaeologist** — Análise módulo a módulo *(expandido pelo Scout após a fase 1)*
  - Camada de domínio (`lib/domain/`)
  - Camada de dados (`lib/data/`)
  - Features Flutter (`lib/features/`)
  - Worker Rust: endpoints, fila de processamento, pipeline OCR→LLM

- [ ] **Detective** — Extrair conhecimento de negócio implícito
  - Fórmula de prioridade: `P = F × R × I × (1 − M)`
  - Fluxo de validação pelo estudante (aceitar/rejeitar classificação)
  - Regras de classificação de erros (taxonomia)
  - Políticas de RLS no Supabase (por tabela)
  - Contratos de API do worker Rust (POST /process-batch, callbacks)

- [ ] **Architect** — Síntese
  - Diagramas C4: Context, Container, Component
  - ERD completo das tabelas do Supabase (schema reconciliado 2026-09-10)
  - Mapa de integração Flutter ↔ Supabase ↔ R2 ↔ Worker
  - Diagrama de sequência: submissão → OCR → LLM → validação → mapa

- [ ] **Writer** — Geração de especificações operacionais em `_reversa_sdd/`

- [ ] **Reviewer** — Validação de gaps com o usuário

## Prioridades

- [ ] Documentar o pipeline de processamento (OCR → LLM → validação → mapa)
- [ ] Especificar os contratos de API do worker Rust (endpoints, payloads, erros)
- [ ] Documentar o schema do Supabase (reconciliado em 2026-09-10)
- [ ] Extrair as regras de RLS aplicadas por tabela
- [ ] Mapear as Edge Functions do Supabase e seus gatilhos

## Após o Discovery — Próximos Fluxos Sugeridos

Quando o SDD estiver em `_reversa_sdd/`:

1. **`/reversa-docs`** — Gerar mini-site de documentação para a apresentação do trabalho
2. **`/reversa-forward`** — Implementar features pendentes com pipeline completo
3. **`/reversa-refactor`** — Identificar oportunidades de melhoria por ROI
4. **`/reversa-pricing-estimate`** — Estimar esforço restante até o MVP final

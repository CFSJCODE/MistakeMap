# Worker Rust arquivado — Tarefas de Implementação

## Pré-requisitos

- [ ] Tratar `worker/` somente como referência histórica; mudança funcional requer aprovação específica.
- [ ] Não usar credenciais de produção em testes.
- [ ] Não substituir Edge Functions sem projeto de migração e critérios de paridade.

## Tarefas

- [ ] T-01, Documentar configuração e rotas históricas sem promover o serviço a backend ativo.
  - Origem no legado: `worker/src/main.rs`, `worker/src/config.rs`, `worker/src/routes/`
  - Critério de pronto: endpoints e requisitos de auth/ambiente estão descritos como legados.
  - Confiança: 🟢
- [ ] T-02, Identificar e manter explícitos os TODOs de OCR, artefatos e LLM.
  - Origem no legado: `worker/src/pipeline.rs`
  - Critério de pronto: nenhuma documentação chama o pipeline de análise funcional.
  - Confiança: 🟢
- [ ] T-03, Registrar divergências de retry, formatos de upload e estado de conclusão.
  - Origem no legado: `worker/src/attempts.rs`, `worker/src/pipeline.rs`, `worker/src/routes/upload_url.rs`
  - Critério de pronto: divergências são testadas/documentadas e não reutilizadas silenciosamente.
  - Confiança: 🟢
- [ ] T-04, Se uma reativação for aprovada separadamente, reconstruir OCR/LLM, retry, contratos e validação fim a fim antes de qualquer deploy.
  - Origem no legado: `worker/src/pipeline.rs`, `BACKEND.md`
  - Critério de pronto: contrato atual Edge é atendido e o worker não marca sucesso sem análise real.
  - Confiança: 🔴

## Tarefas de Teste

- [ ] TT-01, Manter `cargo check` e `cargo clippy -- -D warnings` no código arquivado.
- [ ] TT-02, Adicionar testes para retry/estados caso haja mudança aprovada.
- [ ] TT-03, Testar rejeição de JWT/cron e quotas sem depender de serviços reais.
- [ ] TT-04, Não considerar `cargo test` sem casos de teste como validação funcional.

## Tarefas de Migração de Dados

Não aplicável enquanto o worker permanecer arquivado. 🟢

## Ordem Sugerida

1. Preservar status arquivado e documentação de divergências.
2. Executar somente verificações de manutenção já configuradas.
3. Caso haja autorização para reativar, abrir iniciativa própria; completar pipeline e testes antes do deploy.

## Lacunas Pendentes (🔴)

Reativação está fora de escopo e bloqueada pela incompletude do pipeline. A implementação ativa permanece em `supabase/functions/`.

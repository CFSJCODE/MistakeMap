# Edge Functions Supabase e serviço de IA — Tarefas de Implementação

## Pré-requisitos

- [ ] Disponibilizar variáveis secretas somente no runtime Supabase.
- [ ] Aplicar migrations necessárias em ambiente compatível, sem reescrever histórico.
- [ ] Configurar Gemini, R2 e Supabase Auth no ambiente de execução.

## Tarefas

- [ ] T-01, Implementar autenticação, CORS e escopo do proprietário em endpoints de usuário.
  - Origem no legado: `supabase/functions/_shared/ai_http.ts`
  - Critério de pronto: token inválido e recurso de outro usuário são recusados antes de Gemini.
  - Confiança: 🟢
- [ ] T-02, Implementar upload-url com assinatura e restrição de caminho/tipo/tamanho.
  - Origem no legado: `supabase/functions/upload-url/handler.ts`
  - Critério de pronto: URL é temporária e asset só é aceito após verificação de integridade.
  - Confiança: 🟢
- [ ] T-03, Implementar análise com lock/lease, quota, validação e persistência transacional.
  - Origem no legado: `supabase/functions/_shared/ai_service.ts`, `supabase/functions/_shared/ai_contract.ts`
  - Critério de pronto: concorrência e falhas não produzem análise duplicada/inválida.
  - Confiança: 🟢
- [ ] T-04, Implementar priorização e geração com gabarito privado.
  - Origem no legado: `supabase/functions/_shared/ai_service.ts`, `supabase/functions/_shared/ai_contract.ts`
  - Critério de pronto: 3–5 questões passam contrato e chave não é retornada ao estudante.
  - Confiança: 🟢
- [ ] T-05, Implementar lote autenticado por segredo e endpoint de health sem dados privados.
  - Origem no legado: `supabase/functions/process-batch/handler.ts`, `supabase/functions/health/index.ts`
  - Critério de pronto: lote sem segredo válido não executa; health retorna apenas status operacional.
  - Confiança: 🟢
- [ ] T-06, Adicionar fontes rastreáveis de exercícios existentes aos prompts e ao registro de prática.
  - Origem no legado: `supabase/functions/_shared/ai_service.ts`
  - Critério de pronto: nenhuma questão é persistida sem referência a exercício-fonte permitido.
  - Confiança: 🔴
- [ ] T-07, Criar operação auditável de revisão humana de erro após contrato de produto aprovado.
  - Origem no legado: `supabase/functions/_shared/ai_service.ts` (eventos atuais `pending`)
  - Critério de pronto: somente dono revisa, a transição é validada e registrada sem permitir escrita arbitrária.
  - Confiança: 🔴

## Tarefas de Teste

- [ ] TT-01, Testar autenticação, escopo, CORS e respostas de falha.
- [ ] TT-02, Testar validação do contrato Gemini e fallback de modelo.
- [ ] TT-03, Testar upload inválido, hash incorreto e tentativa concorrente.
- [ ] TT-04, Testar prática com e sem erros históricos e ausência de gabarito no retorno.
- [ ] TT-05, Testar segredo de cron, limite de lote e healthcheck.

## Tarefas de Migração de Dados

- [ ] TM-01, Se validação humana ou origem relacional exigir schema, criar migration aditiva após revisar políticas/RLS; nunca editar migrations aplicadas.

## Ordem Sugerida

1. Auth, ownership, schema e upload formam a fronteira de segurança.
2. Análise precisa de persistência e retry antes do processamento em lote.
3. Garantir gabarito privado na geração atual.
4. Evoluir rastreabilidade-fonte e validação humana depois de decisões explícitas.

## Lacunas Pendentes (🔴)

Definir política de fontes de exercício e fluxo de revisão antes de alterar prompt, schema, RLS ou operações de backend.

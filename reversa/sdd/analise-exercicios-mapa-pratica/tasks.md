# Análise de exercícios, mapa e prática — Tarefas de Implementação

## Pré-requisitos

- [ ] Configurar cliente Supabase e Edge Functions compatíveis.
- [ ] Usar as migrations canônicas sem reescrever histórico aplicado.
- [ ] Preservar a chave privada de prática no servidor.

## Tarefas

- [ ] T-01, Implementar formulário e persistência de exercício/tentativa por texto ou foto.
  - Origem no legado: `appmistakemap/lib/ai/exercise_submission_view.dart`, `appmistakemap/lib/ai/analysis_repository.dart`
  - Critério de pronto: tentativa é persistida com proprietário, matéria e estado coerentes.
  - Confiança: 🟢
- [ ] T-02, Implementar upload validado e recuperação offline.
  - Origem no legado: `appmistakemap/lib/ai/analysis_repository.dart`, `appmistakemap/lib/sync/sincronizador.dart`
  - Critério de pronto: apenas formatos aceitos e arquivos até 8 MB avançam; fila retoma sem duplicar.
  - Confiança: 🟢
- [ ] T-03, Exibir análise com evidências e incerteza explicitamente.
  - Origem no legado: `appmistakemap/lib/ai/analysis_models.dart`, `appmistakemap/lib/ai/analysis_repository.dart`
  - Critério de pronto: resultado `null` não é apresentado como certo ou errado.
  - Confiança: 🟢
- [ ] T-04, Agregar mapa por matéria, conceito, categoria e período.
  - Origem no legado: `appmistakemap/lib/ai/analysis_models.dart`, `appmistakemap/lib/ai/insights_view.dart`
  - Critério de pronto: contagens contam tentativas distintas e filtros alteram o conjunto corretamente.
  - Confiança: 🟢
- [ ] T-05, Solicitar prática e ocultar gabarito antes da resolução.
  - Origem no legado: `appmistakemap/lib/ai/analysis_repository.dart`, `supabase/functions/_shared/ai_service.ts`
  - Critério de pronto: 3–5 itens válidos são retornados sem resposta correta no payload do cliente.
  - Confiança: 🟢
- [ ] T-06, Adicionar fluxo persistente para confirmar, corrigir ou rejeitar evento de erro.
  - Origem no legado: `supabase/functions/_shared/ai_service.ts`; schema em `appmistakemap/database/supabase/migrations/`
  - Critério de pronto: ação auditável do estudante atualiza apenas evento próprio e influencia mapa/prioridade.
  - Confiança: 🔴
- [ ] T-07, Implementar rodada de quiz com resumo e repetição.
  - Origem no legado: `appmistakemap/lib/ai/analysis_repository.dart` (prática individual existente)
  - Critério de pronto: resultado mostra totais, percentuais e assuntos mais errados; iniciar nova rodada é explícito.
  - Confiança: 🔴
- [ ] T-08, Vincular questões geradas a exercícios-fonte existentes.
  - Origem no legado: `supabase/functions/_shared/ai_service.ts`
  - Critério de pronto: ambos os caminhos de geração recebem referências/enunciados existentes e persistem origem verificável.
  - Confiança: 🔴

## Tarefas de Teste

- [ ] TT-01, Testar submissão textual e upload válido/inválido.
- [ ] TT-02, Testar análise determinada e inconclusiva.
- [ ] TT-03, Testar agregação sem duplicidade e filtros temporais.
- [ ] TT-04, Testar gabarito ausente antes de resposta e resumo agregado após rodada.
- [ ] TT-05, Testar origem de exercício em cada questão gerada.

## Tarefas de Migração de Dados

- [ ] TM-01, Projetar migration aditiva para rodada e validação de evento somente após definir contrato e regras de auditoria. As migrations existentes são imutáveis.

## Ordem Sugerida

1. Preservar registro, upload, análise e mapa existentes.
2. Definir modelo e autorização para validação humana antes de alterar prioridade.
3. Implementar rastreabilidade fonte→questão antes de exigir geração grounding.
4. Persistir rodada e respostas; então construir métricas e repetição.

## Lacunas Pendentes (🔴)

Decidir evidência mínima de validação, política de edição/correção do erro, conjunto de fontes aceitável e comportamento de quiz quando a resposta é inconclusiva.

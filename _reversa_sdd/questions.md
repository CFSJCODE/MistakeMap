# Perguntas para Validação — MistakeMap

> Gerado pelo Reviewer em 2026-10-31.
> As respostas estão pendentes; os requisitos relacionados permanecem 🔴.

---

## Pergunta 1

**Contexto:** Análise, mapa e prática — os eventos de erro são sugeridos como `pending`, sem ação persistente para o estudante.
**Spec afetada:** [`_reversa_sdd/analise-exercicios-mapa-pratica/requirements.md`]
**Pergunta:** O estudante pode confirmar, editar ou rejeitar cada classificação? Uma edição deve preservar a sugestão original e registrar motivo/autoria?
**Impacto:** Define transições do evento, autorização, auditoria, UI e quais evidências podem atualizar mapa/prioridade.

**Resposta:** <!-- preencha aqui -->

---

## Pergunta 2

**Contexto:** Geração de prática — os prompts atuais não recebem enunciados-fonte completos e, sem erros, usam apenas o nome da matéria.
**Spec afetada:** [`_reversa_sdd/edge-functions-supabase-servico-ia/requirements.md`]
**Pergunta:** Quais exercícios existentes podem ser fontes: somente os enviados pelo próprio estudante ou também um acervo compartilhado? O que deve ocorrer quando não houver fonte elegível?
**Impacto:** Define consulta/autorização no backend, dados enviados ao modelo e garantia de proveniência para cada questão gerada.

**Resposta:** <!-- preencha aqui -->

---

## Pergunta 3

**Contexto:** Rodada de quiz — o produto pede total/percentual de acertos e erros e assuntos mais errados, mas o modelo atual não persiste uma rodada.
**Spec afetada:** [`_reversa_sdd/analise-exercicios-mapa-pratica/requirements.md`]
**Pergunta:** Respostas inconclusivas devem ficar fora do denominador dos percentuais ou contar como erro? A nova rodada deve reutilizar as mesmas fontes ou escolher outras questões?
**Impacto:** Define o modelo da rodada, fórmulas das métricas e comportamento de repetição.

**Resposta:** <!-- preencha aqui -->

---

## Pergunta 4

**Contexto:** Migrations Supabase — migrations versionadas são a referência local, mas o banco implantado não foi consultado.
**Spec afetada:** [`_reversa_sdd/migracoes-postgresql-supabase/requirements.md`]
**Pergunta:** Qual projeto/branch Supabase é o ambiente canônico para reconciliar o schema e o histórico de migrations?
**Impacto:** É pré-condição para propor migrations novas ou alterar RLS sem divergir do ambiente ativo.

**Resposta:** <!-- preencha aqui -->

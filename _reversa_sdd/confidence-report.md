# Relatório de Confiança — MistakeMap

> Gerado pelo Reviewer em 2026-10-31. Nível Essencial.
> A contagem abaixo soma ocorrências explícitas de marcadores de confiança nos 32 Markdown revisados (24 specs canônicas e 8 documentos globais); arquivos `questions.md` foram excluídos da contagem.

## Resumo Geral

| Nível | Quantidade | Percentual |
|---|---:|---:|
| 🟢 CONFIRMADO | 515 | 84,6% |
| 🟡 INFERIDO | 22 | 3,6% |
| 🔴 LACUNA | 72 | 11,8% |
| **Total** | **609** | **100%** |

**Confiança geral:** **86,4%** (`(515 + 22 × 0,5) / 609`).

> Os valores representam marcações explícitas, não um classificador automático de frases. Lacunas abertas não foram convertidas em confirmações.

## Por Spec

| Spec / unit | 🟢 | 🟡 | 🔴 | Confiança |
|---|---:|---:|---:|---:|
| `aplicativo-flutter-autenticacao-navegacao/` | 50 | 2 | 5 | 89,5% |
| `analise-exercicios-mapa-pratica/` | 55 | 1 | 19 | 74,0% |
| `caderno-local-sincronizacao-offline/` | 57 | 2 | 5 | 90,6% |
| `administracao-metricas-layout/` | 58 | 3 | 1 | 96,0% |
| `edge-functions-supabase-servico-ia/` | 67 | 1 | 10 | 86,5% |
| `migracoes-postgresql-supabase/` | 59 | 1 | 12 | 82,6% |
| `worker-rust-arquivado/` | 52 | 2 | 7 | 86,9% |
| `ci-cd-deploy-web/` | 56 | 2 | 7 | 87,7% |
| Documentos globais | 61 | 8 | 6 | 86,7% |

## Lacunas Pendentes 🔴

### `analise-exercicios-mapa-pratica/`

- **Revisão do diagnóstico pelo estudante** — evento de erro fica `pending`, sem ação persistente. Pergunta correspondente: [`questions.md#pergunta-1`](./questions.md#pergunta-1).
- **Rodada de quiz e tratamento de respostas inconclusivas** — não há sessão/resumo agregado. Pergunta correspondente: [`questions.md#pergunta-3`](./questions.md#pergunta-3).
- **Geração fundamentada em exercícios existentes** — os prompts não recebem enunciados-fonte completos. Pergunta correspondente: [`questions.md#pergunta-2`](./questions.md#pergunta-2).

### `edge-functions-supabase-servico-ia/`

- **Proveniência e autorização de exercícios-fonte** — precisa de fonte permitida e rastreável antes de cada geração. Pergunta correspondente: [`questions.md#pergunta-2`](./questions.md#pergunta-2).
- **Operação auditável de revisão humana** — requer contrato backend/RLS aprovado. Pergunta correspondente: [`questions.md#pergunta-1`](./questions.md#pergunta-1).

### `migracoes-postgresql-supabase/`

- **Paridade do banco implantado** — migrations locais não confirmam o estado remoto. Pergunta correspondente: [`questions.md#pergunta-4`](./questions.md#pergunta-4).

Outras lacunas estão registradas nas perguntas específicas das units, incluindo integração do caderno com o mapa e formato de distribuição Android/Windows.

## Recomendações

- [ ] **P0 — Análise/prática e Edge Functions:** decidir fontes de exercício e fluxo auditável de validação antes de alterar geração ou priorização.
- [ ] **P0 — Banco:** identificar o projeto Supabase canônico e reconciliar migrations antes de propor schema/RLS novos.
- [ ] **P1 — Quiz:** definir tratamento de análise inconclusiva; então persistir rodada, métricas e repetição.
- [ ] **P1 — Entregas das sprints:** localizar PDFs/mockups existentes e confirmar nomes/funções do time e formato de distribuição.
- [ ] **Manutenção:** manter worker Rust arquivado; não o promover a backend ativo enquanto OCR/LLM/retry estiverem incompletos.

## Histórico de Reclassificações

| De | Para | Afirmação | Evidência |
|---|---|---|---|
| — | — | Nenhuma reclassificação de confiança foi necessária após a revisão. Prioridades MoSCoW de lacunas do produto foram corrigidas para Must/Could, sem alterar confiança. | Revisão das oito units contra artefatos de análise e módulos. |

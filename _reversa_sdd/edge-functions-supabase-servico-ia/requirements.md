# Edge Functions Supabase e serviço de IA

## Visão Geral

Esta unit implementa endpoints Deno para upload de imagens, análise de tentativas, geração de prática, processamento em lote e healthcheck. Autentica o usuário, valida contratos e integra Supabase, Gemini e Cloudflare R2. 🟢

## Responsabilidades

- Validar bearer token e limitar operações ao proprietário dos dados. 🟢
- Emitir URL de upload e validar caminho, formato, tamanho e hash. 🟢
- Analisar tentativa com lock/lease, cotas, contrato estruturado e persistência transacional. 🟢
- Gerar 3–5 questões e armazenar gabarito no servidor. 🟢
- Priorizar conceitos por recência e recuperação. 🟢
- Permitir job periódico apenas com segredo de cron e healthcheck público sem dados acadêmicos. 🟢
- Fundamentar cada exercício gerado em enunciado existente. 🔴

## Regras de Negócio

- Análise e prática autenticam no Supabase Auth e escopam leitura ao usuário. 🟢
- Erros de análise só são válidos para resposta incorreta e devem referenciar conceitos declarados. 🟢
- Ranking usa meia-vida de 14 dias e até três acertos subsequentes. 🟢
- Sem erro histórico, prompt de prática usa somente nome da matéria; enunciados-fonte não são incluídos nos prompts atuais. 🟢
- Gabarito de prática é privado até a análise da resposta. 🟢
- Eventos sugeridos são gravados `pending`; ainda não há endpoint de validação pelo estudante. 🟢

## Requisitos Funcionais

> RF-01 a RF-05 descrevem o backend existente; RF-06 e RF-07 são requisitos-alvo 🔴 para cumprir a visão do produto.

| ID | Requisito | Prioridade | Critério de Aceite |
|---|---|---|---|
| RF-01 | Validar identidade Supabase e propriedade antes de análise/prática. 🟢 | Must | Token inválido ou tentativa alheia é recusada sem chamada à IA. |
| RF-02 | Processar análise com lock, lease, limite de cota, schema e transação. 🟢 | Must | Chamada concorrente não duplica análise e persistência é consistente. |
| RF-03 | Validar uploads e emitir URLs assinadas por escopo próprio. 🟢 | Must | Tipo/tamanho/hash/caminho inválidos não avançam. |
| RF-04 | Gerar 3–5 itens com conceito focal e resposta guardada no servidor. 🟢 | Must | Schema inválido é rejeitado e resposta não integra payload de geração. |
| RF-05 | Processar lote com segredo de cron e limite por invocação. 🟢 | Should | Chamada sem segredo é recusada; execução respeita limite configurado. |
| RF-06 | Gerar questões somente com base em exercícios existentes e rastreáveis. 🔴 | Must | Não aceitar geração sem fonte elegível; persistir proveniência. |
| RF-07 | Receber revisão humana de erro com auditoria. 🔴 | Must | Somente proprietário revisa e transições ficam auditáveis. |

## Requisitos Não Funcionais

| Tipo | Requisito inferido | Evidência no código | Confiança |
|---|---|---|---|
| Segurança | Saídas Gemini validadas por schema; conteúdo do usuário tratado como não confiável. | `supabase/functions/_shared/ai_contract.ts`, `ai_http.ts` | 🟢 |
| Disponibilidade | Lock/lease/retry protegem análise concorrente e falhas transitórias. | `supabase/functions/_shared/ai_service.ts` | 🟢 |
| Desempenho | Batch limita chamadas de modelo por invocação. | `supabase/functions/process-batch/handler.ts` | 🟢 |
| Integridade | Upload confirma magic bytes, escopo e SHA-256. | `supabase/functions/upload-url/handler.ts` | 🟢 |

## Critérios de Aceitação

```gherkin
Dado um bearer token válido e uma tentativa própria pronta
Quando analyze-attempt é chamado
Então valida entrada, processa a análise e persiste resultado consistente

Dado um token inválido ou tentativa de outro usuário
Quando analyze-attempt ou generate-practice é chamado
Então retorna erro de autorização sem invocar Gemini

Dado uma saída Gemini fora do schema
Quando o contrato é validado
Então a resposta é rejeitada e não é persistida como análise válida

Dado uma imagem fora do escopo, formato ou limite
Quando o backend valida o asset
Então recusa a análise antes de enviar bytes ao modelo

Dado uma chamada process-batch sem segredo de cron correto
Quando o endpoint recebe a requisição
Então não reivindica nem altera tentativas

Dado que não há erro histórico para a matéria
Quando generate-practice cria exercícios
Então as questões são fundamentadas em enunciados existentes
```

O último cenário é requisito-alvo 🔴, não comportamento existente no backend.

## Prioridade (MoSCoW)

| Requisito | MoSCoW | Justificativa |
|---|---|---|
| Autenticação, propriedade e validação de contrato | Must | Fronteira de segurança e integridade do sistema. |
| Análise idempotente e transacional | Must | Evita duplicidade e estados inconsistentes. |
| Upload assinado e restrito | Must | Imagens pertencem a dados privados do estudante. |
| Geração guardada no servidor | Must | Impede exposição de respostas. |
| Geração grounding e revisão humana | Must | Requisitos explícitos do produto; ainda precisam de implementação coordenada. |

## Rastreabilidade de Código

| Arquivo | Função / Classe | Cobertura |
|---|---|---|
| `supabase/functions/analyze-attempt/handler.ts` | Handler de análise | 🟢 |
| `supabase/functions/generate-practice/handler.ts` | Handler de prática | 🟢 |
| `supabase/functions/upload-url/handler.ts` | Upload assinado | 🟢 |
| `supabase/functions/process-batch/handler.ts` | Job de lote | 🟢 |
| `supabase/functions/_shared/ai_service.ts` | Regras e persistência de IA | 🟢 |
| `supabase/functions/_shared/ai_contract.ts` | Ranking e validação de schemas | 🟢 |
| `supabase/functions/_shared/ai_http.ts` | HTTP, autenticação e CORS | 🟢 |

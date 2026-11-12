# Edge Functions Supabase e serviço de IA — Design Técnico

## Interface

| Símbolo | Entrada | Retorno | Observação |
|---|---|---|---|
| `analyzeAttempt` | DB, `attemptId`, `userId` | Resultado de análise | Reivindica e persiste análise. 🟢 |
| `generatePractice` | DB, usuário, matéria, quantidade, categoria opcional | Conjunto de prática | Guarda gabarito no servidor. 🟢 |
| `rankConcepts` | ocorrências, recuperações, data e categoria | prioridades de conceito | Decaimento temporal e domínio posterior. 🟢 |
| `validateAnalysis` | valor desconhecido | `Analysis` validada | Rejeita schema/categorias inválidos. 🟢 |
| `validatePractice` | valor, quantidade e conceitos-alvo | questões validadas | Confere quantidade e conceito focal. 🟢 |
| `structuredResponse` | schema, instruções, texto e imagens opcionais | JSON desconhecido | Integração comum com Gemini. 🟢 |

Endpoints identificados: `analyze-attempt`, `generate-practice`, `upload-url`, `process-batch` e `health`. Contratos detalhados são definidos pelos handlers e schemas compartilhados, não duplicados aqui. 🟢

## Fluxo Principal

1. Handler aplica CORS e extrai bearer token; cliente Supabase Auth valida identidade. 🟢 (`supabase/functions/_shared/ai_http.ts`)
2. Operação consulta recursos dentro do escopo de usuário; não confia em IDs fornecidos isoladamente. 🟢
3. `analyzeAttempt` bloqueia estados proibidos, adquire lock/lease, verifica quota e carrega texto/asset. 🟢 (`ai_service.ts`)
4. Imagem é lida do R2 e validada por propriedade, formato, tamanho e SHA-256. 🟢
5. Gemini recebe instruções e schema estruturado; o resultado é validado antes de persistência transacional. 🟢
6. Falhas registram execução e estado de retry/dead-letter conforme determinismo/limite. 🟢
7. `generatePractice` calcula conceitos prioritários, chama Gemini, valida itens e armazena gabaritos em tabela privada. 🟢
8. `process-batch` é acionado por segredo de cron; `health` verifica serviços sem expor dados acadêmicos. 🟢

## Fluxos Alternativos

- **Chamada sem autenticação válida:** rejeita antes de consulta privilegiada ou chamada de modelo. 🟢
- **Análise concorrente:** lock/lease evita duplicidade; execução já em andamento é reutilizada/recusada conforme handler. 🟢
- **Saída inválida:** schema rejeita JSON e aplica fallback/erro conforme tentativas de modelo. 🟢
- **Falha transitória:** registra execução reprocessável respeitando cota/limite. 🟢
- **Sem erro histórico:** prompt usa nome da matéria; não inclui exercícios-fonte completos. 🟢

## Dependências

- Deno e `postgres` para runtime e PostgreSQL. 🟢
- Supabase Auth/PostgreSQL para identidade, escopo e persistência. 🟢
- Google Gemini REST para OCR multimodal e geração estruturada. 🟢
- Cloudflare R2 via `aws4fetch` para arquivos. 🟢
- `pg_cron` + `pg_net` para disparo de processamento/health. 🟢

## Decisões de Design Identificadas

| Decisão | Evidência no código | Confiança |
|---|---|---|
| Schema JSON próprio valida retorno de modelo antes de persistir | `supabase/functions/_shared/ai_contract.ts` | 🟢 |
| Ranking usa meia-vida de 14 dias e até três acertos posteriores | `supabase/functions/_shared/ai_contract.ts` | 🟢 |
| Análise utiliza lock/lease, retry e limite diário | `supabase/functions/_shared/ai_service.ts` | 🟢 |
| Gabarito fica em tabela de acesso privado | `supabase/functions/_shared/ai_service.ts` | 🟢 |
| Conteúdo original do exercício não é enviado como fonte de prática | `supabase/functions/_shared/ai_service.ts` | 🟢 |

## Estado Interno

O banco guarda tentativas, análises, assets, execuções de processamento, cotas e gabaritos. `processing_runs` associa execução à tentativa/pipeline e mantém lease/retry. Segredos de Gemini, R2 e cron pertencem ao ambiente servidor. 🟢

## Observabilidade

`health` verifica PostgreSQL e R2; trilha de auditoria, cotas, rate limits e estados de processamento são persistidos no backend. Logs e alertas de operação também são descritos em migrations/configuração. 🟢

## Riscos e Lacunas

- 🔴 A geração não é baseada em exercícios-fonte completos, incluindo caminho sem erros.
- 🔴 Não existe API de revisão/validação humana de eventos de erro.
- 🟡 A fórmula documentada inclui `importance`, mas ranking atual não a aplica explicitamente.
- 🟢 Segredos não devem ser incluídos no cliente nem no repositório.

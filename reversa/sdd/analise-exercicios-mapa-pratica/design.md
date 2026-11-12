# Análise de exercícios, mapa e prática — Design Técnico

## Interface

| Símbolo | Assinatura / entrada | Retorno | Observação |
|---|---|---|---|
| `loadAttempts` | `userId: String` | `Future<List<AttemptRecord>>` | Carrega tentativas e análises do usuário. 🟢 |
| `createAttempt` | usuário, matéria, enunciado, resposta, dificuldade e flags | `Future<String>` | Cria exercício/tentativa e retorna ID. 🟢 |
| `uploadImage` | `attemptId`, nome e bytes | `Future<void>` | Envia por URL assinada e atualiza asset. 🟢 |
| `analyze` | `attemptId: String` | `Future<void>` | Invoca análise autenticada; chamadas repetidas compartilham trabalho em curso. 🟢 |
| `generatePractice` | matéria, quantidade e categoria opcional | `Future<List<PracticeExercise>>` | Quantidade permitida: 3–5. 🟢 |
| `ErrorInsights.fromAttempts` | tentativas | `ErrorInsights` | Normaliza e agrega por matéria, conceito e categoria. 🟢 |

## Fluxo Principal

1. `ExerciseSubmissionView` coleta matéria, enunciado, resposta, dificuldade e foto opcional. 🟢 (`appmistakemap/lib/ai/exercise_submission_view.dart`)
2. `SupabaseAnalysisRepository.createAttempt` persiste exercício/tentativa; sem rede, a fila local pode adiar envio. 🟢 (`analysis_repository.dart`)
3. Para imagem, valida tipo/tamanho, solicita URL de upload, envia bytes e registra asset/hash. 🟢
4. `analyze` invoca `analyze-attempt`; estado e resultado são recarregados do Supabase. 🟢
5. A interface apresenta explicação, transcrição, correção, conceitos e erros sugeridos, distinguindo resultado inconclusivo. 🟢
6. `ErrorInsights.fromAttempts` agrega tentativas distintas; a tela mostra filtros e visualizações por período. 🟢 (`analysis_models.dart`, `insights_view.dart`)
7. Geração de prática chama a Edge Function; o cliente recebe questões, não suas chaves. 🟢

## Fluxos Alternativos

- **Upload inválido:** rejeitar assinatura ou tamanho e não marcar asset como pronto. 🟢
- **Análise inconclusiva:** apresentar revisão, sem contar como acerto/erro determinado. 🟢
- **Offline:** inserir na fila local e tentar sincronizar quando a conectividade retornar. 🟢
- **Erro transitório/conflito:** exibir estado/falha e preservar idempotência da tentativa. 🟢
- **Rodada de quiz:** não existe agregação final; o fluxo permanece por tentativa individual. 🔴

## Dependências

- Supabase Auth/PostgreSQL/Edge Functions: persistência e análise. 🟢
- `image_picker`, `crypto` e HTTP: captura, integridade e upload. 🟢
- Sincronizador/fila local: envio posterior quando offline. 🟢
- Contrato de IA no backend: classificação, prioridade e gabarito privado. 🟢

## Decisões de Design Identificadas

| Decisão | Evidência no código | Confiança |
|---|---|---|
| Resultado booleano ou inconclusivo (`null`) | `appmistakemap/lib/ai/analysis_models.dart` | 🟢 |
| Contagens agregam tentativas distintas; grafo é coocorrência | `appmistakemap/lib/ai/analysis_models.dart` | 🟢 |
| Foto é validada por magic bytes e máximo de 8 MB | `appmistakemap/lib/ai/analysis_repository.dart` | 🟢 |
| Gabarito permanece no servidor até análise da resposta | `supabase/functions/_shared/ai_service.ts` | 🟢 |
| Geração não usa enunciados-fonte completos | `supabase/functions/_shared/ai_service.ts` | 🟢 |

## Estado Interno

`AttemptRecord` mantém IDs, matéria/exercício, texto, status, data e análise opcional. `AttemptAnalysis` guarda correção, explicação, erros e conceitos. A tentativa e os dados da prática são persistidos remotamente; a interface recarrega pelo repositório. 🟢

## Observabilidade

O estado da tentativa, análise e fila é apresentado na interface. Logs, métricas e tratamento de exceções do backend estão especificados na unit de Edge Functions. 🟢

## Riscos e Lacunas

- 🔴 A classificação de erro fica `pending`; a UI não oferece validação persistente.
- 🔴 Prompts não incluem enunciados-fonte completos, inclusive no caminho sem histórico de erro.
- 🔴 Não há entidade ou resumo de rodada com número/percentual de acertos e erros nem opção de nova rodada pelo resultado.
- 🔴 Não foram localizados flashcards ou revisão teórica conectados ao conceito prioritário.
- 🟡 As arestas desenhadas podem ser interpretadas como causalidade, embora codifiquem coocorrência.

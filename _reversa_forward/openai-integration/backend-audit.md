# Auditoria do backend para integração OpenAI

Data: 2026-09-29. Escopo: leitura do código e das migrações locais; nenhum segredo lido, nenhuma chamada OpenAI, conexão ao banco, migração ou publicação executada.

## Estado verificado

- `.reversa/reversa-config.json`: `allowLegacyEdits: false`. Qualquer implementação em `supabase/`, `appmistakemap/` ou `worker/` depende de liberação manual do usuário.
- A migração `supabase/migrations/20260928120000_worker_keepalive_cron.sql` identifica Supabase Edge Functions como backend principal após migração do worker Rust. O estado remoto não foi verificado nesta auditoria.
- `supabase/functions/process-batch/index.ts` promove até cinco tentativas de `pending` para `queued`, baixa todos os assets R2 e marca `completed`. OCR e LLM são apenas TODOs. Portanto, `completed` atualmente não comprova correção ou análise.
- Tentativas de texto sem assets são tratadas como falha. `retryable_failed` nunca é buscado pelo lote, e `queued` não tem recuperação após timeout. `processing_runs` existe no schema, mas não é utilizado.
- `appmistakemap/lib/main.dart` manda `{file_ext}` para `upload-url`, enquanto `supabase/functions/upload-url/index.ts` exige `{filename, content_type}`. Esse contrato precisa ser corrigido antes de validar imagens.
- O formulário atual grava a mesma descrição em `exercises.prompt_text` e `attempts.solution_text`; não há separação confiável entre enunciado, resposta do aluno e observação da dificuldade.
- `ai/README.md` documenta os agentes de desenvolvimento; não constitui uma integração de IA do aplicativo.

## Contratos de dados existentes

As migrações históricas estão em `appmistakemap/database/supabase/migrations/`; a migração de monitoramento mais recente está em `supabase/migrations/`. A aplicação precisa confirmar qual histórico está aplicado no ambiente remoto antes de publicar migrações novas.

| Entidade | Campos relevantes |
|---|---|
| `subjects` | `id`, `user_id`, `name` |
| `concepts` | `id`, `subject_id`, `name`, `description`, `importance` |
| `concept_edges` | `from_concept_id`, `to_concept_id`, `relation`; impede autorrelação |
| `exercises` | `subject_id`, `prompt_text`, `source`, `difficulty` |
| `exercise_concepts` | `exercise_id`, `concept_id`, `weight` |
| `attempts` | `exercise_id`, `user_id`, `solution_text`, `answer`, `attempted_at`, `status`, `version` |
| `corrections` | `attempt_id`, `reference_text`, `reviewed_by` |
| `error_types` | taxonomia global: `name`, `category`, `description`, `severity`, `ontology_version`, `concept_id` |
| `error_events` | `attempt_id`, `error_type_id`, `concept_id`, `evidence_ref`, `confidence`, `status` |
| `mastery_events` | `concept_id`, `attempt_id`, `outcome` |
| `attempt_assets` | `attempt_id`, `object_path`, `sha256` |
| `processing_runs` | `attempt_id`, `pipeline_version`, `status`, `retry_count`, `trace_id`, timestamps; unicidade tentativa/versão |
| `ocr_artifacts` | `attempt_id`, `engine`, `version`, `latex`, `confidence`; sem leitura de cliente |

Estados permitidos de tentativa: `uploading`, `pending`, `queued`, `processing`, `awaiting_review`, `completed`, `retryable_failed`, `dead_letter`, `cancelled`. Estados de evento de erro: `pending`, `confirmed`, `rejected`, `superseded`.

## Riscos concretos a resolver no caminho da integração

1. `process-batch` usa segredo ausente como string vazia e aceita requisição sem header quando a configuração está ausente. Deve recusar operação se o segredo não estiver configurado.
2. As políticas atuais conferem o dono da tentativa, mas não conferem que seu `exercise_id` pertence ao mesmo usuário. `concept_edges`, `exercise_concepts`, `error_events` e `mastery_events` também não verificam todos os extremos das relações. Um serviço privilegiado deve validar propriedade de toda a cadeia antes de leitura ou gravação; uma migração deve impedir relações entre usuários.
3. O cliente pode inserir `attempt_assets.object_path` arbitrário. O processador privilegiado precisa exigir o prefixo `uploads/<dono-da-tentativa>/` e um formato validado, impedindo download de objetos de outro usuário.
4. Status e versão são alteráveis pelo próprio cliente nas políticas atuais. Resultados produzidos pela IA e transições sensíveis devem ser gravados apenas por serviço confiável; a confirmação humana deve usar um contrato específico e limitado.
5. Os corpos HTTP de erro devolvem `String(err)`; conexões, URLs assinadas e respostas do provedor não devem aparecer em respostas ao cliente ou logs.
6. Upload não limita tipo e tamanho reais. Validar JPEG/PNG/WebP, assinatura do arquivo e limite de bytes; rejeitar arquivos incompatíveis antes de enviar à API.
7. O contador `storage_bytes_estimate` é incrementado em cada download, contabilizando novamente o mesmo objeto. Download deve incrementar apenas operação Class B; contabilização de armazenamento pertence à confirmação do upload.
8. A função `check_rate_limit` permite ao autenticado definir chave, limite e janela. Não serve como limite de custo da IA sem uma função restrita derivada de `auth.uid()`.

## Implementação mínima recomendada

1. Corrigir o cadastro para receber enunciado e resposta em campos próprios e corrigir o contrato de upload. Manter a identidade visual atual.
2. Criar módulo compartilhado em `supabase/functions/_shared/` para autenticação, validação, chamadas OpenAI estruturadas e mensagens públicas de erro. Chave apenas no servidor.
3. Criar `analyze-attempt`: autenticar JWT; consultar tentativa e exercício do usuário; adquirir execução idempotente; aceitar texto e imagens válidas; classificar, corrigir e retornar evidências com esquema fechado. Sem evidência suficiente, retornar `awaiting_review`, nunca inventar enunciado ou resultado.
4. Criar migração incremental para análise estruturada e controle da execução: versão/modelo, resposta correta, explicação, transcrição, certeza limitada, resultado certo/errado/indeterminado, erros e conceitos, referência à tentativa, estado de revisão e duração da concessão de execução. Incluir correção das relações de propriedade.
5. Persistir análise, correção e eventos em transação com controle de versão. Eventos da IA começam como `pending`; contagens exibidas distinguem sugestões da IA de confirmações humanas. Tentativa somente chega a `completed` quando existe análise persistida válida.
6. Gerar estatísticas determinísticas das tentativas e eventos do usuário para barras, nuvem e grafo. Uma ligação no grafo representa coocorrência documentada na mesma tentativa; relações de pré-requisito sugeridas por IA devem ter indicação explícita e evidência.
7. Criar `generate-practice`: autenticar, agregar dificuldades do usuário, selecionar evidências e gerar 3–5 exercícios estruturados. Salvar exercícios, gabarito, explicação e tentativas de origem. Validar quantidade, tamanho e taxonomia; não aceitar conteúdo arbitrário ou identificador de outro usuário.
8. Integrar `process-batch` ao mesmo núcleo, com limite de tentativas, recuperação de concessões expiradas e tratamento de 429/timeout. Desativar qualquer conclusão automática pelo download no caminho em uso. Confirmar se o worker Rust continua ativo antes de permitir dois processadores.
9. Adicionar configuração de modelo e limites no backend; recusar chamadas sem chave. Publicação e teste real exigem verificar o projeto remoto, aplicar migração e segredos, publicar funções e exercitar o fluxo autenticado.

## Validação necessária

- Texto com erro conhecido e resposta correta; texto insuficiente; imagem válida e ilegível; tipo/tamanho inválido.
- JWT ausente/inválido; tentativa, exercício, conceito e objeto de outro usuário; segredo cron ausente.
- Resposta malformada, recusa, timeout, 429 e falha do provedor sem exposição de detalhes sensíveis.
- Concorrência de duas chamadas, retry e timeout depois de gravar: uma análise e um conjunto de eventos por versão, sem duplicar custo silenciosamente.
- Gráfico/nuvem/grafo com conjunto fixo de tentativas: contagens e relações devem derivar de registros reais; filtro por usuário, matéria e período; pendentes e rejeitados separados.
- Geração de 3–5 exercícios com evidência de origem e correção persistida.
- Verificação local do TypeScript e testes dos validadores/contratos; análise e testes Flutter. Teste autenticado de ponta a ponta após configuração e publicação, incluindo leitura independente dos resultados persistidos.

## Limites desta entrega

Este arquivo documenta fatos do código local e recomendações; não confirma que funções, schema, cron, RLS ou credenciais do ambiente remoto correspondam aos arquivos. Nenhuma integração foi publicada por esta auditoria.

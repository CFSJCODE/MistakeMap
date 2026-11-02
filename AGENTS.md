# AGENTS.md — MistakeMap

Entrada para Codex e outros agentes. O guia completo (loops do harness e
catálogo do Reversa) está no [CLAUDE.md](CLAUDE.md); em caso de dúvida, ele vale.

## Projeto

MistakeMap mapeia os padrões de erro do estudante.

| Camada | Onde | Tecnologia |
|---|---|---|
| Cliente (Android, Windows, Web) | `appmistakemap/` | Flutter + Dart |
| Caderno de erros (offline + sincronizado) | `appmistakemap/lib/local/`, `lib/sync/caderno_sync.dart` | SQLite (`sqflite`, `ffi`, `ffi_web`) + `shared_preferences`, espelhado em `error_notes` — ver [BANCO_LOCAL.md](appmistakemap/BANCO_LOCAL.md) |
| Banco, Auth, RLS | `appmistakemap/database/supabase/migrations/` | Supabase (Postgres) |
| IA e uploads | `supabase/functions/` | Edge Functions (Deno) + Google Gemini (padrão), Claude Sonnet 5.5 e OpenRouter + Cloudflare R2 |
| Worker OCR/LLM | `worker/` | Rust — **arquivado**, não evoluir |

## Regras não negociáveis

1. Nada de lógica de negócio, OCR ou IA no Flutter: isso fica nas Edge Functions.
2. Nunca envie `service_role` nem qualquer segredo ao cliente; nunca grave segredos em arquivos versionados.
3. Migrations são imutáveis: correção vira migration nova.
4. Proibido HTTP síncrono dentro de trigger; use `pg_cron` + `pg_net`.
5. Todo Dart passa em `flutter analyze` sem avisos.
6. Antes de escrever fora de `_reversa_*/` e `.reversa/`, leia `.reversa/reversa-config.json`
   e respeite `allowLegacyEdits`/`allowedPaths`. Nunca edite esse arquivo por conta própria:
   liberar escrita é ato exclusivo do usuário.

## Critérios de aceite

Flutter (rodar em `appmistakemap/`):

```bash
flutter test --reporter compact          # All tests passed
flutter analyze                          # No issues found
dart format --set-exit-if-changed lib/   # exit 0
```

Edge Functions (rodar em `supabase/functions/`):

```bash
deno check --frozen */index.ts
deno test --frozen --allow-env
```

## Decisões registradas

Decisões já tomadas pelo dono do projeto. Não reabra sem pedido explícito.

**Arquitetura e dados**
- Offline-first (PR #24): o app consulta o Supabase primeiro e cai no SQLite sem rede;
  escritas offline vão para `fila_sync` e sobem ao reconectar; Realtime em
  `subjects`, `attempts` e `attempt_analyses`. Código em `appmistakemap/lib/sync/`.
- Caderno de erros (PR #18) é local (SQLite) e, desde o BancoLocal v3, sincroniza com
  `error_notes` (tombstone `deleted_at`, last-writer-wins por `updated_at`, exclusão vence sempre).
- Exclusões de exercícios/tentativas ficam em `deleted_records` (trigger); o Realtime avisa os
  outros aparelhos e o trigger `block_deleted_reinsert` (SQLSTATE `MM410`) impede que uma fila
  antiga recrie o que foi apagado. Detalhes na seção 5 do BANCO_LOCAL.md.
- Catálogo de exercícios revisados (`catalog_exercises` + `catalog_answer_keys`, gabarito sem
  acesso do cliente): 5 por matéria/assunto/tema. O `generate-practice` serve o catálogo antes
  da IA quando ele fecha a rodada (`_shared/catalog.ts`).
- No `flutter test` o `Sincronizador` nasce desabilitado; `test/sincronizacao_test.dart` liga com SQLite em memória.
- Evite `path_provider` (puxa `jni` e quebra o build Windows sem JDK).
- `web/sqlite3.wasm` deve casar com a versão do pacote `sqlite3` no `pubspec.lock`.
- O workflow `supabase-deploy` aplica migrations no merge do main; Edge Functions
  alteradas podem exigir `supabase functions deploy <nome>`.
- Atualização sem reinstalar: patches de código Dart pelo Shorebird (Android e Windows) e aviso
  de release nativo novo via GitHub Releases (`lib/atualizacao/`). `versao_app.dart` acompanha o
  `version:` do pubspec. Fluxo e configuração em [ATUALIZACOES.md](appmistakemap/ATUALIZACOES.md).
- Provedores de IA (PR #36): toda chamada passa por `structuredResponse()` em
  `_shared/gemini.ts`. Ordem: catálogo (só prática) → roteador por evidência
  (`AI_ROUTING_EVIDENCE`) → rota configurada (`AI_<ANALYSIS|VISION|STUDY|PRACTICE>_PROVIDER`
  ou `AI_PROVIDER`, padrão `gemini`) → cadeia Gemini `gemini-flash-latest` →
  `gemini-3.6-flash` → `gemini-3.5-flash-lite` → `claude-sonnet-5-5` se
  `AI_CLAUDE_FALLBACK_ENABLED=true`. Claude é o único modelo pago: reserva US$ 1 por
  pedido, teto de US$ 100 por 31 dias (`reserve_claude_budget`), falha fechada. OpenRouter só
  entra no roteador com modelos gratuitos; modelo pago configurado à mão nele não tem orçamento no banco. Integração OpenAI (`gpt-4.1-mini`) está preparada
  em `_reversa_forward/openai-integration/`, não ativada. Documentado no README (seção
  "Provedores e modelos de IA").
- Prática (PR #20): `generate-practice` aceita `category` e ranqueia conceitos por
  frequência × recência (meia-vida 14 d), descontando recuperação via `mastery_events`.

**Visual e navegação**
- Identidade Obsidian Glass em **modo claro** com acentos Aurora, linguagem Fluent 2 + Liquid Glass.
  Tokens em `appmistakemap/lib/theme/design_tokens.dart`; paleta em [PALETA.md](appmistakemap/PALETA.md).
  Acentos vivos só como preenchimento; texto colorido usa as variantes "Ink" (≥ 4,5:1).
- Animação de toque uniforme em todos os botões: escala 0,97 em 120 ms.
- Navegação documentada em [NAVEGACAO.md](appmistakemap/NAVEGACAO.md). Mapa é aba com pilha
  própria; trilho lateral em janelas médias/largas; Voltar previsível (PR #31).
- Barra inferior (celular): de ponta a ponta, fatias iguais
  **Início · Lista · Mapa · Estudar · Caderno · Sobre · Mais**. Sem botão Analisar na barra:
  o Mapa já cumpre essa função. "Mais" guarda só Admin e Sair.
- Material de estudo estilo NotebookLM na aba Estudar (PR #27).

**Plataformas e processo**
- iOS adiado até haver Mac ou conta Apple Developer.
- Release Android atual é assinado com chave de debug (não serve para a Play Store).
- Commits de Dart/UI: autor Cláudio, com `Co-Authored-By` do Lucas e do Claude.
- PRs pequenos e focados; cada tópico de trabalho mexe só nos arquivos combinados.

## Em andamento (atualizado em 2026-11-01)

| Frente | Estado | Arquivos de responsabilidade |
|---|---|---|
| PR #32 — barra inferior de ponta a ponta (7 fatias, sem Analisar) | aberto; ajuste da animação do botão em curso | `lib/layout/navigation_shell.dart`, `lib/ai/ai_material_shell.dart`, `NAVEGACAO.md`, `test/navigation_shell_test.dart` |
| Redesenho Fluent + Liquid Glass (dois artefatos de design) | em implementação **sobre a branch do PR #32** | `lib/main.dart` (telas), `lib/theme/**`, `lib/ai/study_material_view.dart`, `insights_view.dart`, `exercise_submission_view.dart`, `material_control_styles.dart`, `lib/caderno_erros.dart`, `lib/admin/**` e os testes dessas telas |

Regra da divisão: token novo em `lib/theme/` é pedido ao tópico do redesenho, não editado
pelo de navegação. O PR do redesenho entra depois do #32 (ou com base na branch dele).

Mergeados recentes: #27 (material de estudo), #29/#30 (barra de vidro líquido), #31 (reestruturação da navegação).

**Pendências conhecidas**
- Fórmula de prioridade P = F × R × I × (1 − M): falta o termo I (importância).
- Fila de revisão; validação dos `error_events` pelo aluno; `focus_concept` some ao recarregar a prática.
- Catálogo ainda sem tela própria de navegação (aparece pela prática); ampliar temas.
- Insights não mostra itens ainda na fila de sync; sync não testado em aparelho real.
- Avisos de validação do Caderno só somem ao salvar de novo.

### Catálogo, comunidade e sincronização (2026-11-01)

- O MistakeMap deve abranger educação básica, estudo independente e, no ensino
  superior inicialmente, Engenharia de Computação, com situações de tecnologia
  adequadas ao nível e sem trocar o objetivo curricular.
- A migration `20261101233126_learning_platform.sql` foi aplicada ao projeto:
  cria o catálogo compartilhado e as publicações. A leitura é para usuários
  autenticados; criar, editar e excluir publicações é restrito a administradores.
  As políticas foram verificadas em transação revertida para os dois papéis.

## Reversa

Framework de engenharia reversa instalado (skills em `.agents/skills/`). Quando o
usuário digitar `reversa` ou `reversa-*`, leia o `SKILL.md` correspondente na
íntegra e siga-o. Fluxos principais: `reversa` (discovery), `reversa-forward`
(specs → código), `reversa-debugger` (bugs), `reversa-docs`, `reversa-agents-help`.
Os artefatos ficam em `_reversa_sdd/`, `_reversa_forward/`, `_reversa_bugs/`,
`_reversa_docs/` e `_reversa_refactor/`.

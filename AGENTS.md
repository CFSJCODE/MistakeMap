# AGENTS.md — MistakeMap

Entrada para Codex e outros agentes. O guia completo (loops do harness e
catálogo do Reversa) está no [CLAUDE.md](CLAUDE.md); em caso de dúvida, ele vale.

## Projeto

MistakeMap mapeia os padrões de erro do estudante.

| Camada | Onde | Tecnologia |
|---|---|---|
| Cliente (Android, Windows, Web) | `appmistakemap/` | Flutter + Dart |
| Caderno de erros offline | `appmistakemap/lib/local/` | SQLite (`sqflite`, `ffi`, `ffi_web`) + `shared_preferences` — ver [BANCO_LOCAL.md](appmistakemap/BANCO_LOCAL.md) |
| Banco, Auth, RLS | `appmistakemap/database/supabase/migrations/` | Supabase (Postgres) |
| IA e uploads | `supabase/functions/` | Edge Functions (Deno) + Google Gemini + Cloudflare R2 |
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

## Reversa

Framework de engenharia reversa instalado (skills em `.agents/skills/`). Quando o
usuário digitar `reversa` ou `reversa-*`, leia o `SKILL.md` correspondente na
íntegra e siga-o. Fluxos principais: `reversa` (discovery), `reversa-forward`
(specs → código), `reversa-debugger` (bugs), `reversa-docs`, `reversa-agents-help`.
Os artefatos ficam em `_reversa_sdd/`, `_reversa_forward/`, `_reversa_bugs/`,
`_reversa_docs/` e `_reversa_refactor/`.

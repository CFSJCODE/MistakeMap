# Dependências e ferramentas

> Valores declarados vêm dos manifests; versões efetivamente resolvidas vêm
> dos lockfiles quando registradas. O worker Rust está arquivado.

## Aplicativo Flutter

- 🟢 Flutter; SDK Dart declarado `^3.13.2`.
- 🟢 CI fixa Flutter `3.47.2`.
- 🟢 Gerenciador: Flutter/Dart pub (`pubspec.yaml`, `pubspec.lock`).
- 🟢 UI: `fluent_ui ^4.16.1` e `liquid_glass_widgets ^1.7.2`.
- 🟢 Backend: `supabase_flutter ^2.8.0`.
- 🟢 Captura de imagem: `image_picker ^1.1.2`.
- 🟢 Persistência: `sqflite ^2.4.4+2`, `sqflite_common_ffi ^2.4.4`,
  `sqflite_common_ffi_web ^1.2.0` e `shared_preferences ^2.5.6`.
- 🟢 Rede e utilitários: `http ^1.2.2`, `crypto ^3.0.7`, `path ^1.9.1`,
  `cupertino_icons ^1.0.8`.
- 🟢 Testes/lints: `flutter_test` e `flutter_lints ^6.0.0`.

## Supabase Edge Functions

- 🟢 TypeScript executado em Deno; CI usa Deno `2.9.x`.
- 🟢 Gerenciador: Deno, com versões travadas em `deno.lock`.
- 🟢 Dependências explícitas: `postgres` `3.4.7` e `aws4fetch` `1.0.20`.
- 🟢 Gemini é chamado pelo serviço compartilhado via HTTP; o contrato/schema
  de saída é mantido no código do projeto.
- 🟢 `deno.json` ativa opções estritas de compilação.

## Worker Rust arquivado

- 🟢 Rust edition 2024; CI usa toolchain `1.98.1`.
- 🟢 Gerenciador: Cargo (`Cargo.toml`, `Cargo.lock`).
- 🟢 Dependências principais declaradas: Axum `0.8.9`, SQLx `0.9.0`,
  Tokio `1.53.1`, AWS SDK S3 `1.145.0`, AWS config `1.12.0`, Serde,
  Reqwest e `jsonwebtoken`.
- 🟢 O worker não é a implementação ativa do backend.

## CI/CD

- 🟢 GitHub Actions: checks Flutter (analyze, format, test), Deno (check e
  test) e Rust (check, clippy e test).
- 🟢 Workflows adicionais publicam Supabase e a aplicação Web.
- 🟡 Credenciais de deploy são configuradas no ambiente do GitHub/Supabase;
  valores de produção não são inventariados aqui.

# CI/CD e deploy Web — Design Técnico

## Interface

| Workflow | Entrada/gatilho | Saída | Observação |
|---|---|---|---|
| CI Flutter | PR, push configurado ou execução manual | analyze, format e test | Flutter 3.47.2. 🟢 |
| CI Deno | Código de Edge Functions | check de entrypoints e tests | Deno 2.9.x. 🟢 |
| CI Rust | `worker/` | check, Clippy com warnings fatais e test | Rust 1.98.1; worker arquivado. 🟢 |
| Deploy Supabase Functions | `main` após gate Deno | Funções publicadas | Segredos permanecem no runtime Supabase. 🟢 |
| Deploy migrations | Alteração de conteúdo de migration | dry-run e push | Deploy serializado e histórico preservado. 🟢 |
| Deploy Web | Mudanças Flutter elegíveis | build release e publicação Vercel | Requer token/IDs como secrets. 🟢 |

## Fluxo Principal

1. Pull request/push aciona `.github/workflows/ci.yml`. 🟢
2. Jobs isolados executam verificações Flutter, Deno e Rust com toolchains fixadas. 🟢
3. Workflow de função repete gate Deno e publica funções a partir do branch principal. 🟢 (`supabase-functions-deploy.yml`)
4. Workflow de banco verifica conteúdo alterado, conecta projeto, roda `db push --dry-run` e só então aplica migrations. 🟢 (`supabase-deploy.yml`)
5. Workflow Web compila Flutter em release e publica artefato na Vercel. 🟢 (`web-deploy-vercel.yml`)
6. Workflow de metadados confere igualdade de cópias canônicas e espelhadas. 🟢

## Fluxos Alternativos

- **Gate falha:** deploy dependente não deve prosseguir. 🟢
- **Nenhuma alteração de migration:** workflow evita reaplicar histórico sem mudança de conteúdo. 🟢
- **Secrets ausentes:** etapa de deploy não dispõe de credenciais; valores devem ser configurados no ambiente. 🟢
- **Mudança apenas em Markdown:** CI principal exclui esse caso conforme configuração. 🟢
- **APK/Windows:** não há workflow confirmado. 🟢

## Dependências

- GitHub Actions runners e toolchains de Dart/Flutter, Deno e Rust. 🟢
- Supabase CLI e secrets do projeto. 🟢
- Vercel CLI e `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`. 🟢
- Configuração versionada em `.github/workflows/`, `supabase/config.toml` e banco. 🟢

## Decisões de Design Identificadas

| Decisão | Evidência no código | Confiança |
|---|---|---|
| CI cobre três toolchains, inclusive worker arquivado | `.github/workflows/ci.yml` | 🟢 |
| Funções Supabase exigem gate Deno | `.github/workflows/supabase-functions-deploy.yml` | 🟢 |
| Migration tem dry-run antes do push | `.github/workflows/supabase-deploy.yml` | 🟢 |
| Deploy Web usa workflow e secrets Vercel dedicados | `.github/workflows/web-deploy-vercel.yml` | 🟢 |
| Não há workflow de build Android/Windows | Inventário de `.github/workflows/` | 🟢 |

## Estado Interno

Workflows têm triggers, jobs, versões de ferramentas e referências a secrets. O estado de produção fica nos provedores; não foi consultado nesta análise. 🟡

## Observabilidade

Status dos jobs e logs são fornecidos pelo GitHub Actions; a configuração de deploy registra os gates e resultados. 🟢

## Riscos e Lacunas

- 🔴 A Sprint pode exigir APK/Windows instalável, mas não há pipeline de distribuição confirmado.
- 🟡 O CI compila o worker arquivado, mantendo um gate de código fora do caminho de produção.
- 🔴 Credenciais e deploy efetivo não foram validados no ambiente remoto.
- 🟢 Deploy de banco deve continuar usando dry-run e migrations aditivas.

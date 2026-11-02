# CI/CD e deploy Web — Tarefas de Implementação

## Pré-requisitos

- [ ] Configurar secrets mínimos em GitHub Actions e Supabase.
- [ ] Manter toolchains de CI compatíveis com manifests/lockfiles.
- [ ] Confirmar branch e ambiente de deploy autorizados.

## Tarefas

- [ ] T-01, Configurar jobs Flutter, Deno e Rust em CI com toolchains fixadas.
  - Origem no legado: `.github/workflows/ci.yml`
  - Critério de pronto: lint/format/check/test executam em PR e reportam status individual.
  - Confiança: 🟢
- [ ] T-02, Publicar Edge Functions somente após gate Deno.
  - Origem no legado: `.github/workflows/supabase-functions-deploy.yml`
  - Critério de pronto: falha no gate bloqueia publicação e nenhum segredo é impresso.
  - Confiança: 🟢
- [ ] T-03, Publicar migrations com verificação de conteúdo, dry-run e serialização.
  - Origem no legado: `.github/workflows/supabase-deploy.yml`
  - Critério de pronto: diff é revisado antes de aplicar; workflow não reescreve migration já aplicada.
  - Confiança: 🟢
- [ ] T-04, Compilar Flutter Web release e publicar na Vercel com secrets.
  - Origem no legado: `.github/workflows/web-deploy-vercel.yml`
  - Critério de pronto: build e deploy ocorrem somente para mudanças/triggers configurados.
  - Confiança: 🟢
- [ ] T-05, Definir e implementar pipeline Android/Windows somente após aprovação de artefatos e canal de distribuição.
  - Origem no legado: ausência de workflow correspondente em `.github/workflows/`
  - Critério de pronto: formato, assinatura, armazenamento e publicação aprovados; pipeline não expõe segredos.
  - Confiança: 🔴

## Tarefas de Teste

- [ ] TT-01, Testar workflow CI com mudança isolada em cada stack.
- [ ] TT-02, Validar que gates falhos bloqueiam respectivos deploys.
- [ ] TT-03, Verificar dry-run de migration em ambiente isolado.
- [ ] TT-04, Validar build Web de release e URL publicada.
- [ ] TT-05, Verificar que logs não exibem tokens/segredos.

## Tarefas de Migração de Dados

Não aplicável diretamente; deploy de schema é coberto pela unit de migrations. 🟢

## Ordem Sugerida

1. Garantir gates de qualidade e secrets.
2. Confirmar dry-run/deploy de banco e funções em ambiente controlado.
3. Validar build Web.
4. Definir formatos móveis/desktop antes de acrescentar jobs de distribuição.

## Lacunas Pendentes (🔴)

Definir se a entrega exige APK, MSIX/instalador Windows ou somente navegação funcional em ambiente de desenvolvimento; não assumir um canal de publicação.

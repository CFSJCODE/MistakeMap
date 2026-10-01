# Migrações do MistakeMap

O diretório canônico é `appmistakemap/database/supabase/migrations/`.
Execute a CLI a partir de `appmistakemap/database`, onde está `supabase/config.toml`.
O diretório `supabase/` na raiz contém apenas as Edge Functions; novas migrações
de banco devem usar o diretório canônico, pois o workflow não lê migrações na raiz.

Toda versão registrada no histórico remoto precisa existir aqui. Se faltar uma,
`supabase db push` recusa a publicação ("Remote migration versions not found in
local migrations directory"). Mudanças aplicadas direto no projeto (SQL Editor,
MCP ou `apply_migration`) devem ser trazidas para este diretório na mesma versão.

## Publicação

O workflow `.github/workflows/supabase-deploy.yml` usa Supabase CLI `2.116.0`,
serializa as publicações e compara os arquivos antes de conectar ao banco.
Alterar apenas autoria ou mensagens de commits não exige publicar migrações.
Uma execução manual faz a verificação mesmo sem mudança de arquivos.

```sh
cd appmistakemap/database
supabase link --project-ref bmdjicshcjpknuaywaph
supabase migration list --linked
supabase db push --linked --dry-run --skip-vault
supabase db push --linked --skip-vault
```

Use apenas credenciais já configuradas no ambiente autorizado. Não as versione.
`--skip-vault` limita a publicação às migrações, sem sincronizar segredos do Vault.
Revise a prévia antes de publicar. Se aparecer uma versão histórica inesperada,
interrompa e compare o esquema com o histórico; não use `--include-all` nem
`migration repair --status reverted` como correção automática.

## Reconciliação de 29/09/2026

O banco já continha os efeitos das 16 migrações de `20260901163259` até
`20260910023647`, mas seu histórico registrava somente duas versões posteriores.
A conferência cobriu tabelas, colunas, constraints, índices, políticas, triggers,
funções, permissões, extensões e jobs. As versões antigas foram registradas como
aplicadas sem executar novamente seus SQLs. O registro é uma operação única de
manutenção; o workflow não repara histórico automaticamente.

- `20260914120000_create_r2_quota_tracking.sql` foi substituída pela versão real
  `20260915004644_create_r2_quota_tracking.sql`, recuperada do histórico remoto.
- `20260928194109_add_role_admin_system.sql` foi recuperada em uma cópia pública
  sanitizada. A versão original continha endereços pessoais para promoção de
  administradores. Esses endereços e a atualização nominal de contas foram
  omitidos; nesta cópia novos perfis recebem `user` e conflitos preservam o perfil
  existente. Essa função difere deliberadamente da original aplicada. Como a
  versão já está registrada, ela não é reaplicada no projeto existente; seus
  usuários, papéis e função remota permanecem preservados. Em outro ambiente,
  provisione administradores separadamente por um canal privilegiado, com
  verificação da identidade. Não use o arquivo como restauração exata da função
  original. Qualquer mudança futura em produção exige uma nova migração.
- O monitor proposto na raiz, `supabase/migrations/20260928120000_worker_keepalive_cron.sql`,
  permanece fora da publicação. A função `health` estava ausente do projeto e sua
  URL retornava HTTP 404 na verificação de 29/09/2026. Antes de ativar o monitor,
  implante e valide essa função; depois mova o SQL para o diretório canônico com
  uma versão posterior à última aplicada. Esse arquivo não cria `process-batch-trigger`.

Esta correção reconcilia 18 versões já aplicadas. A publicação deve terminar com
o banco atualizado, sem executar SQL histórico e sem ativar o monitor pendente.

A cópia integral do histórico anterior foi mantida fora dos arquivos versionados,
em backup local de manutenção. Não publique essa cópia: ela contém o SQL original
com dados pessoais. A reconstrução em banco vazio não foi validada; a migração
histórica de seed depende de um usuário pré-existente em `auth.users`. Este reparo
valida a continuidade do banco existente, não um bootstrap completo de ambiente.

## Reconciliação de 30/09/2026

Três versões haviam sido aplicadas no projeto em 28–29/09/2026 sem chegar ao
repositório. Seus SQLs foram recuperados de `supabase_migrations.schema_migrations`
e conferidos instrução por instrução (MD5) contra o registro remoto:

- `20260928120000_worker_keepalive_cron.sql`: o monitor que estava na raiz em
  `supabase/migrations/` já tinha sido aplicado com essa versão; o arquivo foi
  movido sem alteração. A função `health` continua ausente e o job recebe 404 a
  cada 5 minutos até ela ser implantada.
- `20260929052429_openai_error_analysis.sql`: tabelas `attempt_analyses`,
  `practice_sets`, `practice_answer_keys` e `ai_daily_usage`; taxonomia base de
  `error_types`; políticas somente leitura para resultados da IA; política de
  `attempt_assets` que exige SHA-256; triggers `guard_attempt_ai_state` e
  `guard_analyzed_exercise`. O nome cita OpenAI por histórico; o pipeline atual
  usa Gemini.
- `20260929112200_fix_profiles_rls_recursion.sql`: `public.is_admin()` como
  `SECURITY DEFINER` para eliminar a recursão das políticas de `profiles`.

Os arquivos recuperados receberam só um cabeçalho de comentário. Como as versões
já estão registradas, a publicação não os executa de novo.

> **Atualização:** a função `health` passou a ser publicada pelo CD
> (`supabase-functions-deploy.yml`) com `verify_jwt = false`, e o monitor
> `worker-health-monitor` deixou de receber 404. Detalhes em
> [`BACKEND.md`](../../BACKEND.md), seção 9.

O job `process-batch-every-minute` foi criado manualmente e não pertence a
nenhuma migração. Ele guarda o segredo do cron em texto puro em `cron.job`;
recriá-lo lendo do Vault exige uma nova migração e a rotação do segredo.

# Migrações do MistakeMap

O diretório canônico é `appmistakemap/database/supabase/migrations/`.
Execute a CLI a partir de `appmistakemap/database`, onde está `supabase/config.toml`.
O diretório `supabase/` na raiz continua contendo as Edge Functions e uma proposta
de monitoramento ainda pendente; novas migrações de banco devem usar o diretório
canônico, pois o workflow não lê migrações na raiz.

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

# Exclusão de conta — provisionamento e limites

Implementado em 2026-11-06. Nenhum pedido ou recurso remoto foi criado, processado ou removido durante o desenvolvimento.

## Fluxo

1. `study-platform` registra `request_deletion` somente após confirmação explícita e autenticação da própria sessão nos últimos 10 minutos. O mesmo JWT é validado no Auth, e sua referência de método de autenticação deve comprovar a autenticação recente. Renovação de token ou login em outro aparelho não substituem essa comprovação. O aluno pode cancelar enquanto `pending`. [Claims do Supabase Auth](https://supabase.com/docs/guides/auth/jwt-fields).
2. O worker `account-data` aceita apenas POST `action: process_deletion` com o cabeçalho `x-account-deletion-secret`. JWT de aluno não o autoriza. Uma chamada inicia um único pedido, marcando-o `processing`; não aceita um `user_id` arbitrário do corpo.
3. Novas URLs de upload são recusadas para contas em processamento. O job espera 20 minutos para as URLs PUT existentes (15 minutos) expirarem.
4. Cada execução remove até 25 arquivos ou trabalha por aproximadamente 50 segundos. Confirma a exclusão R2 antes de remover metadados, varre também o prefixo do dono para uploads abandonados e só então chama Auth Admin delete. Falhas deixam a operação retentável, com lease e atraso entre tentativas.
5. Exclusão no Auth aciona as cascatas. Publicações editoriais de autoria da conta são excluídas explicitamente porque a FK antiga é restritiva. Um tombstone técnico (UUIDs, datas, contagens e código sanitizado) permite recuperar confirmação perdida; jobs concluídos são expurgados após 30 dias quando o worker roda.

## Configuração a cargo da publicação

- Aplicar migrations novas em ordem, incluindo `20261106020000_learning_platform_commercial.sql` e `20261106040000_account_lifecycle.sql`.
- Disponibilizar às Edge Functions, sem versionar valores: `ACCOUNT_DELETION_CRON_SECRET` aleatório de pelo menos 32 caracteres, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_URL`, `SUPABASE_DB_URL` e as variáveis R2 já usadas pelo uploader.
- Publicar `account-data` com a verificação JWT do gateway desativada (`--no-verify-jwt`): o worker autentica o segredo dedicado. Nas funções acessadas pelo navegador, como `review-queue`, `study-platform` e `upload-url`, a configuração do gateway permite preflight OPTIONS e o POST continua exigindo JWT válido no próprio handler. Publicar também o uploader atualizado e `study-platform` com a verificação de login recente.
- Agendar POST aproximadamente a cada minuto com `pg_cron` + `pg_net`. Segredo e URL devem vir do Vault na execução; não gravar segredo no SQL de migrations, em argumentos versionados, logs ou frontend. Nenhum cron é criado implicitamente nesta entrega.
- Monitorar `account_deletion_jobs` no servidor: atraso, `last_error`, tentativas e leases expirados. `invalid_asset_path` exige conferir metadados legados; o worker nunca apaga um caminho fora do prefixo do dono.

## Verificação local

`scripts/verify-account-lifecycle.mjs` utiliza PostgreSQL embarcado isolado e R2/Auth simulados, sem chamadas remotas. Exercita período de espera, lotes, falhas R2, isolamento, cascatas e resposta Auth perdida. Os testes Deno cobrem autenticação recente na mesma sessão, parser de listagem, caminhos e recusa de acesso do estudante ao worker.

Não foi validada a execução real de R2/Auth, o agendador, a entrega de exclusão em ambiente publicado ou o esvaziamento de caches de outros aparelhos. Backups e retenção operacional dos provedores seguem suas políticas e não são apagados por este endpoint.

# Publicação da plataforma de estudos (PR #64)

Passo a passo para levar o PR #64 à produção sem janela de erro. Homologado
localmente em 2026-11-08: as 34 migrations do repositório (incluindo as 9 da
plataforma) aplicam em sequência num Postgres 16 limpo, e os cinco scripts
`scripts/verify-*.mjs` passam.

## Por que esta ordem

No merge para a `main`, dois workflows rodam em paralelo:
`supabase-deploy.yml` (migrations) e `supabase-functions-deploy.yml` (funções).
O `generate-practice` novo grava `exercises.focus_concept`, coluna criada pela
migration `20261106050000_practice_focus.sql`. Se a função subir antes da
migration, a prática falha até a migration terminar. Aplicando as migrations
**antes** do merge, o workflow de migrations não encontra nada novo e a janela
deixa de existir.

## 1. Antes de começar

- [ ] Fazer uma cópia do banco (o plano Free não tem backup diário):
  `supabase db dump --linked -f backup-2026-11-08.sql` em `appmistakemap/database`.
- [ ] Conferir que o PR #64 está atualizado com a `main` e com o CI verde.

## 2. Aplicar as migrations (antes do merge)

Na branch do PR, em `appmistakemap/database`:

```bash
supabase db push --linked --dry-run   # deve listar só as 9 migrations novas
supabase db push --linked
```

Migrations esperadas, nesta ordem:

1. `20261106010000_study_review.sql`
2. `20261106020000_learning_platform_commercial.sql`
3. `20261106030000_content_editor.sql`
4. `20261106040000_account_lifecycle.sql`
5. `20261106050000_practice_focus.sql`
6. `20261106060000_teacher_feedback.sql`
7. `20261106070000_student_attempt_analyses.sql`
8. `20261106080000_study_milestones.sql`
9. `20261108010000_account_deletion_cron.sql` (agenda o worker de exclusão)

Nenhuma delas muda o comportamento das funções antigas, então o app atual
continua funcionando entre este passo e o merge.

## 3. Segredo do worker de exclusão

Gerar um valor aleatório **uma vez** e usá-lo nos dois lugares abaixo, sem
gravá-lo em arquivo versionado nem colar em chat:

```bash
SEGREDO=$(openssl rand -hex 32)
supabase secrets set ACCOUNT_DELETION_CRON_SECRET="$SEGREDO" --project-ref bmdjicshcjpknuaywaph
```

No SQL Editor do Supabase (o Vault guarda criptografado):

```sql
select vault.create_secret('https://bmdjicshcjpknuaywaph.supabase.co', 'mistakemap_project_url');
select vault.create_secret('<o mesmo SEGREDO>', 'account_deletion_cron_secret');
```

O job `account-deletion-worker` roda a cada minuto, mas só chama a função
quando existe pedido de exclusão pendente ou job em andamento. Sem os dois
segredos ele não faz nada.

## 4. Merge do PR #64

O merge publica as funções (`review-queue`, `study-platform`, `account-data`,
`upload-url` e as alteradas). O workflow de migrations deve terminar com
"nada a aplicar".

## 5. Conferências logo após o merge

```sql
-- job agendado
select jobname, schedule from cron.job where jobname = 'account-deletion-worker';
-- últimas respostas do pg_net (deve aparecer 200 depois do primeiro pedido)
select created, status_code, error_msg from net._http_response order by created desc limit 5;
-- fila de exclusão
select status, last_error, attempts, not_before from public.account_deletion_jobs order by created_at desc limit 10;
```

- [ ] `POST /functions/v1/account-data` sem o cabeçalho do segredo responde 401.
- [ ] `OPTIONS` em `review-queue` e `study-platform` responde 200 (CORS).
- [ ] App web abre "Seu estudo de hoje" sem erro para uma conta nova.

## 6. Cenários de homologação

Usar duas contas de aluno (A e B), uma de professor e uma de administrador.

| # | Cenário | Esperado |
|---|---|---|
| 1 | A analisa um exercício e confirma um erro | Item aparece na revisão de hoje |
| 2 | A rejeita um erro sugerido | Some do Mapa; análise original preservada |
| 3 | A pede prática sem ter confirmado nada | Mensagem "Não há erros confirmados" e convite para conferir |
| 4 | A responde a revisão offline e reconecta | Resposta enviada uma vez, sem duplicar |
| 5 | A começa a revisão no celular e continua na web | Sessão retomada no mesmo ponto |
| 6 | Professor cria turma; A entra pelo código | B não vê a turma |
| 7 | A compartilha progresso e depois revoga | Professor deixa de ver na hora |
| 8 | Professor envia parecer numa tarefa | Só A lê o parecer |
| 9 | Professor envia exercício; admin publica | Aparece no catálogo sem gabarito para alunos |
| 10 | A exporta os dados | Arquivo com os próprios dados, nada de B |
| 11 | A pede exclusão logo após entrar | Pedido aceito; após ~20 min fotos, dados e login somem |
| 12 | A pede exclusão com sessão antiga | Recusado com "Entre novamente" |

## 7. Se algo der errado

- Função com erro: reimplantar a versão anterior da função a partir da `main`
  anterior ao merge (`git checkout <sha> -- supabase/functions` e
  `supabase functions deploy <nome>`). As migrations são aditivas e não
  quebram as funções antigas.
- Pausar o worker de exclusão: `select cron.unschedule('account-deletion-worker');`
- Migrations são imutáveis: qualquer correção vira migration nova.

## Pendência relacionada

O job antigo `process-batch-every-minute` ainda guarda o próprio segredo em
texto no comando do `cron.job` (pendência já listada no README: "mover o
segredo do pg_cron para o Vault"). Vale aplicar o mesmo padrão desta migration
num PR separado e trocar o valor do `WORKER_CRON_SECRET` depois.

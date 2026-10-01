# Validação do esquema existente para reconciliar migrações

Data da coleta de fingerprint: 2026-09-29 01:57:10 -03:00.
Projeto: MistakeMap.
Escopo: auditoria somente leitura das 17 migrações locais e dos metadados correspondentes no Supabase, para reconciliar o histórico sem reaplicar alterações existentes.

## Resultado

As 16 versões anteriores à migração de cotas têm seus efeitos finais presentes no banco. Não foi encontrada divergência estrutural bloqueante para registrá-las como aplicadas, desde que sejam preservadas as alterações posteriores que substituíram funções, jobs e políticas anteriores.

A migração local de cotas `20260914120000` também coincide estruturalmente com a tabela remota, mas deve ser reconciliada com a versão remota `20260915004644`. A recuperação das migrações remotas ausentes e a alteração do histórico são etapas separadas conduzidas pelo agente principal.

Esta auditoria não reaplicou SQL, não executou funções de negócio, não enviou notificações e não mudou registros do histórico. O único arquivo produzido por este agente é este relatório.

## Matriz das 16 versões

| Versão local | Evidência observada no banco | Tratamento seguro |
|---|---|---|
| `20260901163259_create_initial_schema` | Dez tabelas iniciais, colunas, tipos, defaults, nulabilidade, PK/FK/checks, índices, políticas e RLS presentes conforme o SQL local. | Registrar como aplicada sem recriar objetos. |
| `20260901173121_create_profiles` | Estrutura de `profiles` e constraints acadêmicas presentes. A política inicial foi substituída pelas políticas da migração posterior de administração. | Registrar como aplicada preservando as políticas posteriores. |
| `20260901174242_seed_first_user_profile` | Consulta de existência do perfil original retornou somente `true`; seus campos pessoais não foram extraídos. | Registrar como aplicada; não reinserir nem sobrescrever o perfil. |
| `20260901174740_add_rate_limiting` | Tabela `rate_limits`, duas funções com corpos coincidentes, defaults `300, 60` e dez triggers originais ativos. | Registrar como aplicada. |
| `20260901184234_enable_pg_cron_and_pg_net` | `pg_cron` instalado em `pg_catalog` e `pg_net` em `extensions`. `pgcrypto` também presente em `extensions`. | Registrar como aplicada. |
| `20260901185730_create_storage_usage_function` | `storage_usage_bytes` presente e com corpo coincidente; contém o endurecimento posterior de search_path e permissões. | Registrar como aplicada preservando o endurecimento posterior. |
| `20260901190159_create_storage_alert_state` | Tabela, constraint singleton, RLS e registro singleton presentes. | Registrar como aplicada. |
| `20260901190314_create_storage_alert_function` | `check_storage_and_alert` presente, corpo coincidente e configuração de segurança esperada. | Registrar como aplicada. |
| `20260901190457_schedule_storage_alert_check` | Job `check-storage-usage` ativo, schedule `*/15 * * * *`; igualdade do comando com o esperado confirmada por booleano. | Registrar como aplicada sem duplicar o job. |
| `20260901190751_enforce_storage_cap` | Função `enforce_storage_cap` com corpo coincidente e trigger ativo em `storage.objects`. | Registrar como aplicada. |
| `20260901195255_create_r2_storage_alert` | `r2_alert_state` presente. Função e job síncronos originais substituídos pelo fluxo assíncrono posterior. | Registrar como aplicada; não restaurar a versão antiga. |
| `20260901195752_fix_r2_threshold_int_overflow` | Conversão explícita para bigint incorporada à função final de processamento do R2. | Registrar como aplicada; preservar a versão final. |
| `20260901200215_fix_r2_alert_async_pattern` | Coluna `pending_request_id`, funções request/process e jobs correspondentes presentes. Função antiga `check_r2_storage_and_alert(text)` ausente conforme previsto. | Registrar como aplicada. |
| `20260904162246_fix_r2_bucket_name` | Defaults das duas funções iguais a `mistakemap`. Jobs ativos com comandos esperados; request em `*/15 * * * *` e process em `2-59/15 * * * *`. | Registrar como aplicada; preservar o bucket final. |
| `20260909161252_fix_security_advisor_findings` | search_path e permissões EXECUTE efetivas confirmadas conforme a matriz abaixo. | Registrar como aplicada. |
| `20260910023647_create_ingestion_pipeline_tables` | Quatro tabelas do pipeline, extensões de `attempts` e `error_types`, constraints, índices, RLS, duas políticas e trigger de rate limit em `attempt_assets` presentes. | Registrar como aplicada. |

Todos os tipos, defaults e atributos NOT NULL das 19 tabelas públicas observadas conferem com os efeitos esperados das migrações locais e da extensão posterior de `profiles`. As PK/FK/checks relevantes e os índices previstos foram conferidos no catálogo.

## Funções e permissões

As comparações de corpo abaixo usam MD5 do texto com whitespace removido. O hash é uma evidência de igualdade do conteúdo consultado, não uma assinatura de segurança. Nenhum corpo de função remoto foi incluído neste relatório.

| Função final | MD5 normalizado local = remoto | search_path | EXECUTE anon | EXECUTE authenticated |
|---|---|---|---|---|
| `check_rate_limit` | `130217c8549d7aba55992b3ae5231a48` | `public` | Não | Sim |
| `enforce_rate_limit` | `e073624cdaf535226dd5e1590dbacf39` | `public` | Não | Não |
| `storage_usage_bytes` | `bd8148bfa2f20b04368020d2b504f54a` | `public` | Não | Não |
| `enforce_storage_cap` | `e6aa43dc63bbb53b6f68b634580892bb` | `public` | Não | Não |
| `check_storage_and_alert` | `464ca5ddec4cfbfd757f84df2c681890` | `public, extensions` | Não | Não |
| `request_r2_storage_usage` | `ada9d74973486ea12a3585c6f4a6f7db` | `public, extensions` | Não | Não |
| `process_r2_storage_usage` | `45ea904c13958865e3c158ffb6695297` | `public, extensions` | Não | Não |

`check_rate_limit`, `enforce_rate_limit` e as três funções de alertas/R2 são SECURITY DEFINER, conforme os arquivos. `storage_usage_bytes` e `enforce_storage_cap` mantêm SECURITY INVOKER. Os onze triggers de rate limit (dez originais e o adicional de assets) e o trigger de storage cap estavam habilitados.

## Fingerprint do esquema

Valor agregado observado antes da comparação posterior do agente principal:

`dadc3677ece726bd58bf1c21c827d6c5`

| Componente | Fingerprint |
|---|---|
| relations | `519471f6c0dbd2e1a3e5af215f0f3e7a` |
| constraints | `08ffa92a6c432f19355bcb5e11be37c2` |
| indexes | `6d1f3c362700afef5c9dd5114e14d6de` |
| policies | `c92976e552e7fc380eb9bfc1335e6370` |
| functions | `95c34a3f87acb4380362a71ba4266b9a` |
| triggers | `d171db7e136ac9bee392db3b350f974a` |
| extensions | `af791892e34f0998c4e829a93b51163e` |
| cron | `47064c9fc29f5abc85452efc9cbb3eed` |

O fingerprint exclui `supabase_migrations` e dados de aplicação. Considera relações públicas, colunas/defaults/ACL/RLS, constraints, índices, políticas, funções/configuração/ACL, triggers públicos e o trigger de storage cap, extensões e definições dos jobs de cron. Os corpos de função e comandos do cron entram apenas por hashes internos; a consulta retorna somente fingerprints.

A execução idêntica após o registro do histórico permite comprovar a ausência de alteração desses metadados. Não substitui backup nem comprova integridade de linhas de dados, valores de sequência, segredos, serviços externos ou elementos fora do escopo. Não há resultado pós-reparo registrado neste relatório.

### Consulta SELECT reutilizável

```sql
with component_data as (
select 'relations'::text as component, coalesce(jsonb_agg(jsonb_build_object(
 'schema', n.nspname, 'name', c.relname, 'kind', c.relkind,
 'rls', c.relrowsecurity, 'force_rls', c.relforcerowsecurity, 'acl', c.relacl,
 'columns', (select jsonb_agg(jsonb_build_object('name', a.attname,
 'type', format_type(a.atttypid,a.atttypmod), 'not_null', a.attnotnull,
 'identity', a.attidentity, 'generated', a.attgenerated,
 'default', pg_get_expr(d.adbin,d.adrelid)) order by a.attnum)
 from pg_attribute a left join pg_attrdef d
 on d.adrelid=a.attrelid and d.adnum=a.attnum
 where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped)
) order by n.nspname,c.relname),'[]'::jsonb) as metadata
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind in ('r','p','v','m','S')
union all
select 'constraints',coalesce(jsonb_agg(jsonb_build_object(
 'table',c.relname,'name',co.conname,'definition',pg_get_constraintdef(co.oid),
 'validated',co.convalidated) order by c.relname,co.conname),'[]'::jsonb)
from pg_constraint co join pg_class c on c.oid=co.conrelid
join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'
union all
select 'indexes',coalesce(jsonb_agg(jsonb_build_object(
 'table',tablename,'name',indexname,'definition',indexdef)
 order by tablename,indexname),'[]'::jsonb)
from pg_indexes where schemaname='public'
union all
select 'policies',coalesce(jsonb_agg(jsonb_build_object(
 'table',tablename,'name',policyname,'command',cmd,'roles',roles,
 'permissive',permissive,'using',qual,'check',with_check)
 order by tablename,policyname),'[]'::jsonb)
from pg_policies where schemaname='public'
union all
select 'functions',coalesce(jsonb_agg(jsonb_build_object(
 'name',p.proname,'arguments',pg_get_function_identity_arguments(p.oid),
 'returns',pg_get_function_result(p.oid),'language',l.lanname,
 'source_hash',md5(p.prosrc),'config',p.proconfig,'acl',p.proacl,
 'security_definer',p.prosecdef,'volatility',p.provolatile,
 'strict',p.proisstrict,'defaults',pg_get_expr(p.proargdefaults,0))
 order by p.proname,pg_get_function_identity_arguments(p.oid)),'[]'::jsonb)
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
join pg_language l on l.oid=p.prolang where n.nspname='public'
union all
select 'triggers',coalesce(jsonb_agg(jsonb_build_object(
 'schema',n.nspname,'table',c.relname,'name',t.tgname,'enabled',t.tgenabled,
 'definition',pg_get_triggerdef(t.oid))
 order by n.nspname,c.relname,t.tgname),'[]'::jsonb)
from pg_trigger t join pg_class c on c.oid=t.tgrelid
join pg_namespace n on n.oid=c.relnamespace
where not t.tgisinternal and (n.nspname='public'
 or (n.nspname='storage' and t.tgname='enforce_storage_cap'))
union all
select 'extensions',coalesce(jsonb_agg(jsonb_build_object(
 'name',e.extname,'schema',n.nspname,'version',e.extversion)
 order by e.extname),'[]'::jsonb)
from pg_extension e join pg_namespace n on n.oid=e.extnamespace
union all
select 'cron',coalesce(jsonb_agg(jsonb_build_object(
 'name',jobname,'schedule',schedule,'active',active,'command_hash',md5(command))
 order by jobname,jobid),'[]'::jsonb) from cron.job
), hashes as (
select component,md5(metadata::text) as fingerprint from component_data
)
select md5(string_agg(component||':'||fingerprint,E'\n' order by component)) as schema_fingerprint,
jsonb_object_agg(component,fingerprint order by component) as component_fingerprints
from hashes;
```

## Limites e observações

- A leitura de dados de aplicação restringiu-se à existência do perfil seed original e do singleton de alerta. Não foram extraídos nomes, e-mails, conteúdo dos perfis, registros de autenticação, segredos, respostas HTTP ou comandos brutos do cron.
- Não foi realizado teste ponta a ponta de login, acesso por papel de usuário, ingestão, alertas por e-mail ou operações no R2. Configuração presente não equivale à comprovação operacional desses fluxos.
- As políticas atuais de `profiles` consultam a própria tabela, o que indica possível recursão de RLS preexistente. Essa observação não foi validada por execução sob papel de usuário; ela não impede reconciliar o histórico preservando o esquema atual e não foi corrigida por este agente.
- Reaplicar os SQLs históricos pode duplicar políticas, constraints, triggers e seed ou reintroduzir funções/jobs superados. A recomendação é recuperar o histórico comprovado e preservar os efeitos finais existentes.


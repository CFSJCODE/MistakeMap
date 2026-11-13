-- Central da Equipe (app MistakeMap Equipe): saúde do sistema, erros do
-- backend, diagnósticos e ferramentas de QA para contas admin/developer.
--
-- Tudo roda no servidor com checagem de papel (is_team_member()); o cliente
-- só recebe agregados técnicos, nunca e-mail, conteúdo de exercício ou
-- resposta de IA. Nenhuma credencial sai do backend.

-- ─── Registro de erros das Edge Functions ──────────────────────────────────
-- Gravado pelas Edge Functions com a service_role (ai_http.failure). Só o
-- código público do erro, a função e o status HTTP: sem usuário, sem texto.
create table if not exists public.team_error_events (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  function_name text not null check (char_length(function_name) between 1 and 64),
  code text not null check (char_length(code) between 1 and 64),
  status integer not null check (status between 0 and 599),
  source text not null default 'edge' check (source in ('edge', 'qa_probe'))
);

create index if not exists team_error_events_time_idx
  on public.team_error_events (occurred_at desc);

alter table public.team_error_events enable row level security;
revoke all on public.team_error_events from public, anon, authenticated;
grant select, insert, delete on public.team_error_events to service_role;
grant usage on sequence public.team_error_events_id_seq to service_role;

-- Retenção de 30 dias.
select cron.schedule(
  'team-error-events-prune',
  '23 4 * * *',
  $$delete from public.team_error_events where occurred_at < now() - interval '30 days'$$
);

create or replace function public.team_require_member()
returns void
language plpgsql
security definer
set search_path = ''
stable
as $$
begin
  if auth.uid() is null or not public.is_team_member() then
    raise exception 'team_access_required' using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.team_require_member() from public, anon;
grant execute on function public.team_require_member() to authenticated;

-- ─── Retrato do sistema ──────────────────────────────────────────────────────
create or replace function public.team_console_snapshot()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_day date := (now() at time zone 'UTC')::date;
  v_result jsonb;
begin
  perform public.team_require_member();

  select jsonb_build_object(
    'captured_at', now(),
    'usage', jsonb_build_object(
      'profiles', (select count(*) from public.profiles),
      'profiles_by_role', (select coalesce(jsonb_object_agg(role, n), '{}'::jsonb)
                             from (select role, count(*) n from public.profiles group by role) r),
      'new_profiles_7d', (select count(*) from public.profiles
                            where created_at >= now() - interval '7 days'),
      'active_users_24h', (select count(distinct user_id) from public.attempts
                             where attempted_at >= now() - interval '24 hours'),
      'active_users_7d', (select count(distinct user_id) from public.attempts
                            where attempted_at >= now() - interval '7 days'),
      'exercises', (select count(*) from public.exercises),
      'attempts_24h', (select count(*) from public.attempts
                         where attempted_at >= now() - interval '24 hours'),
      'attempts_7d', (select count(*) from public.attempts
                        where attempted_at >= now() - interval '7 days'),
      'analyses_24h', (select count(*) from public.attempt_analyses
                         where created_at >= now() - interval '24 hours'),
      'analyses_7d', (select count(*) from public.attempt_analyses
                        where created_at >= now() - interval '7 days'),
      'question_responses_7d', (select count(*) from public.question_responses
                                  where created_at >= now() - interval '7 days'),
      'study_sessions_7d', (select count(*) from public.study_sessions
                              where started_at >= now() - interval '7 days'),
      'error_notes', (select count(*) from public.error_notes where deleted_at is null),
      'schools', (select count(*) from public.schools),
      'school_members', (select count(*) from public.school_members where status = 'active')
    ),
    'ai', jsonb_build_object(
      'requests_today', (select coalesce(jsonb_object_agg(kind, n), '{}'::jsonb)
                           from (select kind, sum(requests) n from public.ai_daily_usage
                                  where usage_day = v_day group by kind) k),
      'last_analysis_at', (select max(created_at) from public.attempt_analyses),
      'last_model', (select model from public.attempt_analyses order by created_at desc limit 1),
      'models_7d', (select coalesce(jsonb_agg(m order by m.analyses desc), '[]'::jsonb)
                      from (select model, count(*) analyses
                              from public.attempt_analyses
                             where created_at >= now() - interval '7 days'
                             group by model) m),
      'api_24h', (select coalesce(jsonb_agg(a order by a.calls desc), '[]'::jsonb)
                    from (select model, count(*) calls,
                                 count(*) filter (where status_code = 0 or status_code >= 400) failures,
                                 count(*) filter (where status_code = 429) throttled,
                                 round(percentile_cont(0.5) within group (order by elapsed_ms))::int median_ms
                            from public.ai_api_events
                           where started_at >= now() - interval '24 hours'
                           group by model) a)
    ),
    'pipeline', jsonb_build_object(
      'by_status', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb)
                      from (select status, count(*) n from public.processing_runs group by status) s),
      'leased_now', (select count(*) from public.processing_runs
                       where status = 'processing' and lease_until > now()),
      'failures_24h', (select count(*) from public.processing_runs
                         where updated_at >= now() - interval '24 hours'
                           and status in ('retryable_failed', 'dead_letter'))
    ),
    'errors', jsonb_build_object(
      'total_24h', (select count(*) from public.team_error_events
                      where occurred_at >= now() - interval '24 hours' and source = 'edge'),
      'invalid_ai_output_24h', (select count(*) from public.team_error_events
                                  where occurred_at >= now() - interval '24 hours'
                                    and code = 'invalid_ai_output'),
      'by_code_24h', (select coalesce(jsonb_agg(e order by e.n desc), '[]'::jsonb)
                        from (select function_name, code, count(*) n, max(occurred_at) last_at
                                from public.team_error_events
                               where occurred_at >= now() - interval '24 hours'
                               group by function_name, code) e),
      'recent', (select coalesce(jsonb_agg(r order by r.occurred_at desc), '[]'::jsonb)
                   from (select occurred_at, function_name, code, status, source
                           from public.team_error_events
                          order by occurred_at desc limit 20) r)
    ),
    'cron', (select coalesce(jsonb_agg(c order by c.jobname), '[]'::jsonb)
               from (select j.jobname, j.schedule, j.active,
                            (select max(d.start_time) from cron.job_run_details d
                              where d.jobid = j.jobid) last_run_at,
                            (select d.status from cron.job_run_details d
                              where d.jobid = j.jobid order by d.start_time desc limit 1) last_status,
                            (select count(*) from cron.job_run_details d
                              where d.jobid = j.jobid
                                and d.start_time >= now() - interval '24 hours') runs_24h,
                            (select count(*) from cron.job_run_details d
                              where d.jobid = j.jobid and d.status = 'failed'
                                and d.start_time >= now() - interval '24 hours') failures_24h
                       from cron.job j) c),
    'billing', jsonb_build_object(
      'invoices', (select coalesce(jsonb_agg(i), '[]'::jsonb)
                     from (select status, demo, count(*) n from public.school_invoices
                            group by status, demo) i),
      'demo_schools', (select count(*) from public.school_billing_settings where demo)
    ),
    'database', jsonb_build_object(
      'last_migration', (select max(version) from supabase_migrations.schema_migrations),
      'size_bytes', pg_catalog.pg_database_size(pg_catalog.current_database()),
      'deletion_jobs_pending', (select count(*) from public.account_deletion_jobs
                                  where completed_at is null)
    )
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.team_console_snapshot() from public, anon;
grant execute on function public.team_console_snapshot() to authenticated;

-- ─── Diagnósticos do servidor ────────────────────────────────────────────────
-- Cada item: id, título, situação (ok, warn, fail) e detalhe em PT-BR.
create or replace function public.team_run_diagnostics()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_out jsonb := '[]'::jsonb;
  v_list text;
  v_n bigint;
  v_m bigint;
begin
  perform public.team_require_member();

  -- 1. RLS ligada em todas as tabelas públicas.
  select string_agg(c.relname, ', ' order by c.relname), count(*)
    into v_list, v_n
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;
  v_out := v_out || jsonb_build_object(
    'id', 'rls', 'title', 'RLS ligada em todas as tabelas',
    'status', case when v_n = 0 then 'ok' else 'fail' end,
    'detail', case when v_n = 0 then 'Nenhuma tabela pública sem RLS.'
                   else 'Sem RLS: ' || v_list end);

  -- 2. Gabaritos e telemetria fechados para o cliente.
  select string_agg(t, ', ' order by t), count(*)
    into v_list, v_n
    from unnest(array['question_bank_keys', 'catalog_answer_keys',
                      'practice_answer_keys', 'study_quiz_keys',
                      'platform_session_keys', 'ai_api_events',
                      'school_payment_events', 'team_error_events']) t
   where pg_catalog.to_regclass('public.' || t) is not null
     and (pg_catalog.has_table_privilege('authenticated', 'public.' || t, 'SELECT')
       or pg_catalog.has_table_privilege('anon', 'public.' || t, 'SELECT'));
  v_out := v_out || jsonb_build_object(
    'id', 'secrets', 'title', 'Gabaritos e telemetria fora do alcance do app',
    'status', case when v_n = 0 then 'ok' else 'fail' end,
    'detail', case when v_n = 0 then 'Nenhum gabarito ou log legível pelo cliente.'
                   else 'Legível pelo cliente: ' || v_list end);

  -- 3. Funções SECURITY DEFINER sem search_path fixo.
  select string_agg(p.proname, ', ' order by p.proname), count(*)
    into v_list, v_n
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) cfg
                      where cfg like 'search_path=%');
  v_out := v_out || jsonb_build_object(
    'id', 'search_path', 'title', 'Funções privilegiadas com search_path fixo',
    'status', case when v_n = 0 then 'ok' else 'warn' end,
    'detail', case when v_n = 0 then 'Todas as funções SECURITY DEFINER fixam o search_path.'
                   else 'Sem search_path: ' || v_list end);

  -- 4. Jobs do pg_cron ativos e sem falha na última hora.
  select count(*) filter (where not j.active),
         (select count(*) from cron.job_run_details d
           where d.status = 'failed' and d.start_time >= now() - interval '1 hour')
    into v_n, v_m
    from cron.job j;
  v_out := v_out || jsonb_build_object(
    'id', 'cron', 'title', 'Rotinas agendadas (pg_cron)',
    'status', case when v_n = 0 and v_m = 0 then 'ok' else 'fail' end,
    'detail', format('%s job(s) inativo(s); %s execução(ões) com falha na última hora.', v_n, v_m));

  -- 5. Fila de análises sem itens mortos.
  select count(*) filter (where status = 'dead_letter'),
         count(*) filter (where status = 'processing' and lease_until < now() - interval '15 minutes')
    into v_n, v_m
    from public.processing_runs;
  v_out := v_out || jsonb_build_object(
    'id', 'queue', 'title', 'Fila de processamento',
    'status', case when v_n = 0 and v_m = 0 then 'ok' else 'warn' end,
    'detail', format('%s item(ns) em dead letter; %s com lease vencido há mais de 15 min.', v_n, v_m));

  -- 6. Exclusões de conta dentro do prazo.
  select count(*) into v_n
    from public.account_deletion_jobs
   where completed_at is null and not_before < now() - interval '1 hour';
  v_out := v_out || jsonb_build_object(
    'id', 'deletion', 'title', 'Exclusões de conta no prazo',
    'status', case when v_n = 0 then 'ok' else 'warn' end,
    'detail', format('%s exclusão(ões) atrasada(s) há mais de 1 hora.', v_n));

  -- 7. Escola de demonstração nunca cobrada de verdade.
  select count(*) into v_n
    from public.school_invoices i
    join public.school_billing_settings b on b.school_id = i.school_id
   where b.demo and not i.demo;
  v_out := v_out || jsonb_build_object(
    'id', 'demo_billing', 'title', 'Escolas demo sem cobrança real',
    'status', case when v_n = 0 then 'ok' else 'fail' end,
    'detail', format('%s fatura(s) real(is) em escola marcada como demo.', v_n));

  -- 8. Respostas inválidas da IA nas últimas 24 horas.
  select count(*) into v_n
    from public.team_error_events
   where code = 'invalid_ai_output' and occurred_at >= now() - interval '24 hours';
  v_out := v_out || jsonb_build_object(
    'id', 'invalid_ai_output', 'title', 'Respostas inválidas da IA (24 h)',
    'status', case when v_n = 0 then 'ok' when v_n < 5 then 'warn' else 'fail' end,
    'detail', format('%s ocorrência(s) de invalid_ai_output.', v_n));

  -- 9. Papéis válidos e ao menos um administrador.
  select count(*) filter (where role = 'admin'),
         count(*) filter (where role not in ('admin', 'developer', 'user'))
    into v_n, v_m
    from public.profiles;
  v_out := v_out || jsonb_build_object(
    'id', 'roles', 'title', 'Papéis das contas',
    'status', case when v_n > 0 and v_m = 0 then 'ok' else 'fail' end,
    'detail', format('%s administrador(es); %s papel(éis) fora do padrão.', v_n, v_m));

  return v_out;
end;
$$;

revoke all on function public.team_run_diagnostics() from public, anon;
grant execute on function public.team_run_diagnostics() to authenticated;

-- ─── Ferramentas de QA ───────────────────────────────────────────────────────
-- Evento de teste: confere de ponta a ponta que o registro de erros e a
-- Central leem o mesmo lugar.
create or replace function public.team_log_probe()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.team_require_member();
  insert into public.team_error_events (function_name, code, status, source)
  values ('central-equipe', 'qa_probe', 0, 'qa_probe');
end;
$$;

revoke all on function public.team_log_probe() from public, anon;
grant execute on function public.team_log_probe() to authenticated;

-- Recomeça os dados de estudo da PRÓPRIA conta, só em contas de teste
-- (@mistakemap.dev) da equipe: apaga os exercícios (e tentativas/análises em
-- cascata), arquiva o caderno e semeia os exemplos de novo. Nunca toca em
-- escolas, cobrança ou em outra conta.
create or replace function public.team_reset_own_demo_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_exercises integer;
  v_notes integer;
  v_seeded integer;
begin
  perform public.team_require_member();
  select email into v_email from auth.users where id = v_uid;
  if v_email is null or v_email not like '%@mistakemap.dev' then
    raise exception 'only_test_accounts' using errcode = '42501';
  end if;

  delete from public.exercises e
   using public.subjects s
   where s.id = e.subject_id and s.user_id = v_uid;
  get diagnostics v_exercises = row_count;

  update public.error_notes
     set deleted_at = now(), updated_at = now()
   where user_id = v_uid and deleted_at is null;
  get diagnostics v_notes = row_count;

  v_seeded := public.seed_example_exercises();

  return jsonb_build_object(
    'exercises_removed', v_exercises,
    'notes_archived', v_notes,
    'examples_created', v_seeded);
end;
$$;

revoke all on function public.team_reset_own_demo_data() from public, anon;
grant execute on function public.team_reset_own_demo_data() to authenticated;

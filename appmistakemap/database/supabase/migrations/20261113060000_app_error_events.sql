-- Erros do app (aluno e equipe) para a Central da Equipe: achar falhas em
-- produção e validar um patch ou release pela versão em que o erro aparece.
--
-- O app envia só o tipo da exceção, o primeiro quadro do código do próprio
-- app (arquivo:linha) e a versão/build/patch/plataforma. Nunca a mensagem da
-- exceção (pode conter texto do aluno), e-mail ou conteúdo. O autor fica
-- gravado só para limitar o volume por conta e contar usuários afetados; a
-- Central nunca devolve o id.

create table if not exists public.app_error_events (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  reporter uuid not null,
  app text not null check (app in ('aluno', 'equipe')),
  platform text not null check (char_length(platform) between 1 and 16),
  version text not null check (char_length(version) between 1 and 24),
  build integer not null check (build between 0 and 1000000),
  patch integer check (patch between 0 and 1000000),
  kind text not null check (char_length(kind) between 1 and 80),
  location text not null check (char_length(location) between 1 and 160),
  fatal boolean not null default false
);

create index if not exists app_error_events_time_idx
  on public.app_error_events (occurred_at desc);
create index if not exists app_error_events_reporter_idx
  on public.app_error_events (reporter, occurred_at desc);

alter table public.app_error_events enable row level security;
revoke all on public.app_error_events from public, anon, authenticated;
grant select, insert, delete on public.app_error_events to service_role;
grant usage on sequence public.app_error_events_id_seq to service_role;

-- Retenção de 30 dias, como o registro das Edge Functions.
select cron.schedule(
  'app-error-events-prune',
  '27 4 * * *',
  $$delete from public.app_error_events where occurred_at < now() - interval '30 days'$$
);

-- Gravação pelo app de qualquer conta logada. Limite de 30 erros por conta
-- por hora: um loop de erro não enche a tabela. Acima do limite, descarta em
-- silêncio (o app não precisa saber).
create or replace function public.report_app_error(
  p_app text,
  p_platform text,
  p_version text,
  p_build integer,
  p_patch integer,
  p_kind text,
  p_location text,
  p_fatal boolean default false
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if (select count(*) from public.app_error_events
       where reporter = v_uid and occurred_at > now() - interval '1 hour') >= 30 then
    return;
  end if;
  insert into public.app_error_events
    (reporter, app, platform, version, build, patch, kind, location, fatal)
  values (
    v_uid,
    case when p_app = 'equipe' then 'equipe' else 'aluno' end,
    left(coalesce(nullif(trim(p_platform), ''), 'desconhecida'), 16),
    left(coalesce(nullif(trim(p_version), ''), '?'), 24),
    greatest(0, least(coalesce(p_build, 0), 1000000)),
    case when p_patch is null then null else greatest(0, least(p_patch, 1000000)) end,
    left(coalesce(nullif(trim(p_kind), ''), 'Erro'), 80),
    left(coalesce(nullif(trim(p_location), ''), 'desconhecido'), 160),
    coalesce(p_fatal, false)
  );
end;
$$;

revoke all on function public.report_app_error(text, text, text, integer, integer, text, text, boolean) from public, anon;
grant execute on function public.report_app_error(text, text, text, integer, integer, text, text, boolean) to authenticated;

-- Central: erros do app por versão e por assinatura (tipo + local), para ver
-- se um patch trouxe ou resolveu um erro. Só agregados; sem o id do autor.
create or replace function public.team_app_errors(p_hours integer default 72)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_since timestamptz := now() - make_interval(hours => greatest(1, least(coalesce(p_hours, 72), 720)));
begin
  perform public.team_require_member();
  return jsonb_build_object(
    'hours', extract(epoch from now() - v_since)::integer / 3600,
    'total', (select count(*) from public.app_error_events where occurred_at >= v_since),
    'users', (select count(distinct reporter) from public.app_error_events where occurred_at >= v_since),
    'fatal', (select count(*) from public.app_error_events where occurred_at >= v_since and fatal),
    'by_version', coalesce((
      select jsonb_agg(v order by v->>'last_at' desc)
        from (select jsonb_build_object(
                       'app', app, 'version', version, 'build', build,
                       'patch', patch, 'n', count(*),
                       'users', count(distinct reporter),
                       'last_at', max(occurred_at)) v
                from public.app_error_events
               where occurred_at >= v_since
               group by app, version, build, patch) x), '[]'::jsonb),
    'top', coalesce((
      select jsonb_agg(t order by (t->>'n')::integer desc)
        from (select jsonb_build_object(
                       'kind', kind, 'location', location, 'n', count(*),
                       'users', count(distinct reporter),
                       'fatal', bool_or(fatal),
                       'first_at', min(occurred_at),
                       'last_at', max(occurred_at),
                       'platforms', array_agg(distinct platform),
                       'versions', array_agg(distinct
                         version || '+' || build ||
                         coalesce(' p' || patch, ''))) t
                from public.app_error_events
               where occurred_at >= v_since
               group by kind, location
               order by count(*) desc
               limit 15) y), '[]'::jsonb),
    'recent', coalesce((
      select jsonb_agg(r order by r->>'occurred_at' desc)
        from (select jsonb_build_object(
                       'occurred_at', occurred_at, 'app', app,
                       'platform', platform, 'version', version,
                       'build', build, 'patch', patch, 'kind', kind,
                       'location', location, 'fatal', fatal) r
                from public.app_error_events
               where occurred_at >= v_since
               order by occurred_at desc
               limit 20) z), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.team_app_errors(integer) from public, anon;
grant execute on function public.team_app_errors(integer) to authenticated;

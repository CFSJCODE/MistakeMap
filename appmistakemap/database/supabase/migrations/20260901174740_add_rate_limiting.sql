-- Rate limiting agressivo: 300 solicitações por minuto por usuário,
-- agregado entre todas as tabelas de escrita do usuário.
--
-- Contador de janela fixa (fixed window). A função check_rate_limit()
-- também fica disponível via RPC para uso futuro em código de backend
-- (Edge Functions, API), fora dos triggers.

create table if not exists public.rate_limits (
  rate_key text not null,
  window_start timestamptz not null,
  request_count integer not null default 1,
  primary key (rate_key, window_start)
);

-- Acesso direto à tabela é negado: só a função (security definer) escreve nela.
alter table public.rate_limits enable row level security;

create or replace function public.check_rate_limit(
  p_key text,
  p_limit integer default 300,
  p_window_seconds integer default 60
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_window_start timestamptz;
  v_count integer;
begin
  v_window_start := to_timestamp(
    floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds
  );

  insert into public.rate_limits (rate_key, window_start, request_count)
  values (p_key, v_window_start, 1)
  on conflict (rate_key, window_start)
    do update set request_count = public.rate_limits.request_count + 1
  returning request_count into v_count;

  delete from public.rate_limits
  where rate_key = p_key
    and window_start < v_window_start - make_interval(secs => p_window_seconds);

  return v_count <= p_limit;
end;
$$;

grant execute on function public.check_rate_limit(text, integer, integer) to authenticated;

create or replace function public.enforce_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.check_rate_limit('user:' || coalesce(auth.uid()::text, 'anon'), 300, 60) then
    raise exception 'rate limit exceeded: máximo de 300 solicitações por minuto'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'subjects', 'concepts', 'concept_edges', 'exercises', 'exercise_concepts',
    'attempts', 'corrections', 'error_events', 'mastery_events', 'profiles'
  ]
  loop
    execute format(
      'create trigger enforce_rate_limit before insert on public.%I
       for each row execute function public.enforce_rate_limit()',
      t
    );
  end loop;
end $$;

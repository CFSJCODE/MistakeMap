-- Exclusão em duas etapas: interrompe novos uploads e aguarda os PUTs assinados
-- (900s) expirarem antes de remover R2 e Auth. Nenhum segredo ou cron implícito.
create table public.account_deletion_jobs (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique,
  -- Sem FK: o tombstone permite concluir/verificar arquivos após Auth cascade.
  -- Apenas identificador técnico, sem email, conteúdo ou credenciais.
  user_id uuid not null,
  status text not null default 'waiting' check(status in ('waiting','processing','retry','completed')),
  not_before timestamptz not null default now()+interval '20 minutes',
  next_attempt_at timestamptz not null default now(),
  lease_token uuid,
  lease_until timestamptz,
  attempts integer not null default 0 check(attempts>=0),
  removed_objects integer not null default 0 check(removed_objects>=0),
  last_error text check(last_error in ('storage_unavailable','auth_unavailable','invalid_asset_path','lease_lost','internal_error')),
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  check((status='completed')=(completed_at is not null))
);
create index account_deletion_runnable on public.account_deletion_jobs(next_attempt_at,not_before) where status<>'completed';
alter table public.account_deletion_jobs enable row level security;
revoke all on public.account_deletion_jobs from public,anon,authenticated;
grant all on public.account_deletion_jobs to service_role;
comment on table public.account_deletion_jobs is 'Tombstones técnicos de exclusão; apagar concluídos após 30 dias. Worker account-data exige segredo dedicado, nunca JWT de aluno.';

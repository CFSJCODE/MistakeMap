-- Proposta para uma NOVA migration. Não aplicada ao Supabase.
-- Revisar o histórico remoto antes de publicar; não alterar migrations antigas.
begin;

create table public.notebook_entries (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  disciplina text not null check (length(trim(disciplina)) > 0),
  titulo text not null check (length(trim(titulo)) > 0),
  descricao text not null,
  tipo_erro text not null check (tipo_erro in ('conceitual','calculo','interpretacao','atencao')),
  revisado boolean not null default false,
  criado_em timestamptz not null,
  atualizado_em timestamptz not null
);
create index notebook_entries_owner_updated on public.notebook_entries(user_id, atualizado_em);
alter table public.notebook_entries enable row level security;
revoke all on public.notebook_entries from public, anon, authenticated;
grant select, insert, update, delete on public.notebook_entries to authenticated;
create policy notebook_owner_read on public.notebook_entries for select to authenticated
  using (user_id = (select auth.uid()));
create policy notebook_owner_insert on public.notebook_entries for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy notebook_owner_update on public.notebook_entries for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy notebook_owner_delete on public.notebook_entries for delete to authenticated
  using (user_id = (select auth.uid()));

commit;


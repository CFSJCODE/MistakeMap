-- Sincronização do Caderno de erros e exclusões entre aparelhos.
--
-- 1. error_notes: cópia no servidor do caderno que antes vivia só no SQLite.
--    O id (uuid) nasce no aparelho; excluir é marcar deleted_at (tombstone),
--    nunca apagar a linha, para que os outros aparelhos fiquem sabendo.
-- 2. deleted_records: registro das exclusões de exercícios e tentativas, que
--    hoje são apagados de verdade (DELETE). Alimenta o aviso em tempo real e a
--    barreira contra ressurreição.
-- 3. Barreira: uma fila antiga de outro aparelho não restaura o que foi
--    apagado. Nota excluída não volta (o UPDATE é ignorado), edição mais velha
--    que a gravada não sobrescreve (last-writer-wins por updated_at) e
--    exercício/tentativa excluídos não podem ser recriados com o mesmo id
--    (erro MM410, que o app trata tirando a operação da fila).
-- 4. Realtime: as duas tabelas entram na publicação. Exclusão vira INSERT ou
--    UPDATE, então o Realtime aplica a RLS e cada aluno só recebe as suas.

-- ─── error_notes ────────────────────────────────────────────────────────────
create table public.error_notes (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  subject text not null check (char_length(btrim(subject)) between 1 and 120),
  title text not null check (char_length(title) <= 200),
  description text not null check (char_length(description) <= 5000),
  error_type text not null
    check (error_type in ('conceitual', 'calculo', 'interpretacao', 'atencao')),
  reviewed boolean not null default false,
  created_at timestamptz not null,
  -- Relógio do aparelho que fez a alteração: decide quem vence (LWW).
  updated_at timestamptz not null,
  -- Tombstone: preenchido na exclusão, nunca volta a nulo.
  deleted_at timestamptz,
  -- Relógio do servidor: cursor da leitura incremental dos aparelhos.
  synced_at timestamptz not null default clock_timestamp()
);

create index error_notes_owner_sync_idx on public.error_notes (user_id, synced_at);

alter table public.error_notes enable row level security;

create policy error_notes_owner_read on public.error_notes
  for select to authenticated using (user_id = (select auth.uid()));
create policy error_notes_owner_insert on public.error_notes
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy error_notes_owner_update on public.error_notes
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Sem DELETE para o cliente: a exclusão é o tombstone.
revoke all on public.error_notes from public, anon, authenticated;
grant select, insert, update on public.error_notes to authenticated;
grant all on public.error_notes to service_role;

create or replace function public.guard_error_note() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    if new.user_id <> old.user_id or new.id <> old.id then
      raise exception 'error note ownership cannot change' using errcode = '42501';
    end if;
    -- Barreira: nota excluída não volta, nem por fila antiga nem por edição.
    if old.deleted_at is not null then
      return null;
    end if;
    -- LWW: edição feita antes da que já está gravada perde. A exclusão vence
    -- sempre, mesmo com relógio atrasado, para nada apagado reaparecer.
    if new.deleted_at is null and new.updated_at < old.updated_at then
      return null;
    end if;
    new.created_at := old.created_at;
  end if;
  if new.deleted_at is not null then
    -- O tombstone guarda só o necessário para propagar a exclusão.
    new.title := '';
    new.description := '';
  end if;
  new.synced_at := pg_catalog.clock_timestamp();
  return new;
end;
$$;

revoke execute on function public.guard_error_note() from public, anon, authenticated;

create trigger guard_error_note before insert or update on public.error_notes
  for each row execute function public.guard_error_note();

-- ─── deleted_records ────────────────────────────────────────────────────────
create table public.deleted_records (
  table_name text not null check (table_name in ('exercises', 'attempts')),
  record_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  deleted_at timestamptz not null default clock_timestamp(),
  primary key (table_name, record_id)
);

create index deleted_records_owner_idx on public.deleted_records (user_id, deleted_at);

alter table public.deleted_records enable row level security;

create policy deleted_records_owner_read on public.deleted_records
  for select to authenticated using (user_id = (select auth.uid()));

-- Escrita só pelos triggers abaixo (security definer).
revoke all on public.deleted_records from public, anon, authenticated;
grant select on public.deleted_records to authenticated;
grant all on public.deleted_records to service_role;

create or replace function public.record_deletion() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  dono uuid;
begin
  if tg_table_name = 'attempts' then
    dono := old.user_id;
  else
    select s.user_id into dono from public.subjects s where s.id = old.subject_id;
    -- Exclusão em cascata da matéria: a linha dela já saiu.
    dono := coalesce(dono, auth.uid());
  end if;
  -- Conta sendo apagada (cascata de auth.users): não há a quem avisar, e o
  -- registro violaria a chave estrangeira e desfaria a exclusão da conta.
  if dono is not null and exists (select 1 from auth.users u where u.id = dono) then
    insert into public.deleted_records (table_name, record_id, user_id)
    values (tg_table_name, old.id, dono)
    on conflict do nothing;
  end if;
  return old;
end;
$$;

revoke execute on function public.record_deletion() from public, anon, authenticated;

create trigger record_exercise_deletion after delete on public.exercises
  for each row execute function public.record_deletion();
create trigger record_attempt_deletion after delete on public.attempts
  for each row execute function public.record_deletion();

-- Barreira: o mesmo id não renasce depois de excluído. O app gera os ids no
-- aparelho e reenvia a fila com upsert, então sem isto uma fila antiga de
-- outro aparelho recriaria o exercício apagado.
create or replace function public.block_deleted_reinsert() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if exists (
    select 1 from public.deleted_records d
    where d.table_name = tg_table_name and d.record_id = new.id
  ) then
    raise exception 'record was deleted on another device'
      using errcode = 'MM410', hint = tg_table_name || ':' || new.id::text;
  end if;
  return new;
end;
$$;

revoke execute on function public.block_deleted_reinsert() from public, anon, authenticated;

create trigger block_deleted_exercise before insert on public.exercises
  for each row execute function public.block_deleted_reinsert();
create trigger block_deleted_attempt before insert on public.attempts
  for each row execute function public.block_deleted_reinsert();

-- ─── Realtime ───────────────────────────────────────────────────────────────
do $$
declare
  tabela text;
begin
  foreach tabela in array array['error_notes', 'deleted_records'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = tabela
    ) then
      execute format('alter publication supabase_realtime add table public.%I', tabela);
    end if;
  end loop;
end
$$;

#!/usr/bin/env bash
# Testes das funções da TI da escola (migration 20261113180000) num Postgres
# local descartável. Nunca toca o banco publicado.
# Uso: scripts/verify-school-it.sh   (precisa de initdb/pg_ctl/psql 15+,
# rodando como usuário que não seja root)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mig="$root/appmistakemap/database/supabase/migrations"
here="$root/scripts/school_it"
bin="${PG_BIN:-$(dirname "$(command -v initdb 2>/dev/null || ls /usr/lib/postgresql/*/bin/initdb | tail -1)")}"
tmp="$(mktemp -d)"
port="${PG_TEST_PORT:-55434}"
cleanup() { "$bin/pg_ctl" -D "$tmp/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$tmp"; }
trap cleanup EXIT
"$bin/initdb" -D "$tmp/data" -U postgres -A trust >/dev/null
"$bin/pg_ctl" -D "$tmp/data" -o "-p $port -k $tmp -c listen_addresses=127.0.0.1" -l "$tmp/log" start >/dev/null
run() { psql -h "$tmp" -p "$port" -U postgres -d postgres -v ON_ERROR_STOP=1 -q "$@"; }
run -f "$root/scripts/schools_rls/supabase_stub.sql"
# Colunas do Auth que as funções da TI leem (o Supabase real já tem).
run <<'SQL'
alter table auth.users add column raw_user_meta_data jsonb, add column last_sign_in_at timestamptz;
create table auth.sessions(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz default now(), updated_at timestamptz default now(),
  refreshed_at timestamp, not_after timestamptz, user_agent text, ip inet);
SQL
sed 's/^create extension if not exists "pgcrypto" with schema extensions;//I' \
  "$mig/20260901163259_create_initial_schema.sql" | run
run -c "grant select, insert, update, delete on all tables in schema public to authenticated"
run <<'SQL'
create table public.attempt_analyses (
  attempt_id uuid primary key references public.attempts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  analysis jsonb not null default '{}'
);
alter table public.attempt_analyses enable row level security;
revoke all on public.attempt_analyses from anon,authenticated;
create table if not exists public.profiles(id uuid primary key references auth.users(id) on delete cascade, role text not null default 'user');
SQL
run -c "insert into public.error_types(name) values ('calculo'),('conceito'),('sinal'),('interpretacao'),('procedimento'),('unidade'),('outro') on conflict do nothing"
run -f "$mig/20261102003100_catalog_exercises.sql"
run -f "$mig/20261106020000_learning_platform_commercial.sql"
run -o /dev/null -f "$mig/20261108030000_question_bank.sql"
run -f "$mig/20261111050000_schools_and_roles.sql"
run -f "$mig/20261111200000_class_map_assignments.sql"
run -f "$mig/20261111210000_school_plans_quota.sql"
run -f "$mig/20261111223000_signup_profiles.sql"
run -f "$mig/20261112170000_school_billing.sql"
run -f "$mig/20261112190000_school_billing_demo_guard.sql"
run -f "$mig/20261112210000_school_reports.sql"
run -f "$mig/20261113180000_school_it_admin.sql"
run -o /dev/null -f "$here/tests.sql" 2>&1 | sed -e 's/^psql:[^ ]* //' -e 's/^NOTICE:  //'
[ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
# Edge Function contra o mesmo banco (precisa de deno).
if command -v deno >/dev/null; then
  SUPABASE_DB_URL="postgres://postgres@127.0.0.1:$port/postgres" \
    deno run --config "$root/supabase/functions/deno.json" --allow-env --allow-net \
    "$root/scripts/school_it/service_test.ts"
fi
# Seed de demonstração da TI: roda duas vezes (idempotente).
run -o /dev/null -f "$here/seed_demo_ti.sql"
run -o /dev/null -f "$here/seed_demo_ti.sql"
run -At <<'SQL' | grep -qx 't'
select count(*) >= 8 from public.school_audit_log a join public.schools s on s.id = a.school_id
where s.name = 'Colégio Nexo — Unidade Centro (demonstração)'
SQL
echo "ok: seed de demonstração da TI (idempotente)"
echo "verify-school-it: todos os testes passaram"

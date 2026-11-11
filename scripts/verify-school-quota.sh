#!/usr/bin/env bash
# Testes de planos, cota coletiva e aluno ativo (migration 20261111210000) num
# Postgres local descartável. Nunca toca o banco publicado.
# Uso: scripts/verify-school-quota.sh   (precisa de initdb/pg_ctl/psql 15+,
# rodando como usuário que não seja root)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mig="$root/appmistakemap/database/supabase/migrations"
here="$root/scripts/school_quota"
bin="${PG_BIN:-$(dirname "$(command -v initdb 2>/dev/null || ls /usr/lib/postgresql/*/bin/initdb | tail -1)")}"
tmp="$(mktemp -d)"
port="${PG_TEST_PORT:-55433}"
cleanup() { "$bin/pg_ctl" -D "$tmp/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$tmp"; }
trap cleanup EXIT
"$bin/initdb" -D "$tmp/data" -U postgres -A trust >/dev/null
"$bin/pg_ctl" -D "$tmp/data" -o "-p $port -k $tmp -c listen_addresses=''" -l "$tmp/log" start >/dev/null
run() { psql -h "$tmp" -p "$port" -U postgres -d postgres -v ON_ERROR_STOP=1 -q "$@"; }
run -f "$root/scripts/schools_rls/supabase_stub.sql"
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
SQL
run -c "insert into public.error_types(name) values ('calculo'),('conceito'),('sinal'),('interpretacao'),('procedimento'),('unidade'),('outro') on conflict do nothing"
run -f "$mig/20261102003100_catalog_exercises.sql"
run -f "$mig/20261106020000_learning_platform_commercial.sql"
run -o /dev/null -f "$mig/20261108030000_question_bank.sql"
run -f "$mig/20261111050000_schools_and_roles.sql"
run -f "$mig/20261111200000_class_map_assignments.sql"
run -f "$mig/20261111210000_school_plans_quota.sql"
run -o /dev/null -f "$here/tests.sql" 2>&1 | sed -e 's/^psql:[^ ]* //' -e 's/^NOTICE:  //'
[ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
echo "verify-school-quota: todos os testes passaram"

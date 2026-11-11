#!/usr/bin/env bash
# Testes do contrato e LGPD da escola (migration 20261111074500) num Postgres
# local descartável. Nunca toca o banco publicado.
# Confere também que o texto gravado pela migration é o mesmo dos arquivos
# em appmistakemap/database/legal/ (hash SHA-256).
# Uso: scripts/verify-school-agreements.sh   (precisa de initdb/pg_ctl/psql 15+)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mig="$root/appmistakemap/database/supabase/migrations"
legal="$root/appmistakemap/database/legal"
here="$root/scripts/school_agreements"
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
# is_admin() existe no Supabase desde 20260929112200; aqui, um admin fixo.
run -c "create function public.is_admin() returns boolean language sql stable as \$\$ select auth.uid() = 'e0000000-0000-4000-8000-000000000001'::uuid \$\$"
run -c "grant execute on function public.is_admin() to authenticated, service_role"
run -c "insert into public.error_types(name) values ('calculo'),('conceito'),('sinal'),('interpretacao'),('procedimento'),('unidade'),('outro') on conflict do nothing"
run -f "$mig/20261102003100_catalog_exercises.sql"
run -f "$mig/20261106020000_learning_platform_commercial.sql"
run -f "$mig/20261111050000_schools_and_roles.sql"
run -f "$mig/20261111074500_school_agreements.sql"
sha() { sha256sum "$legal/$1/1.0.md" | cut -d' ' -f1; }
run -o /dev/null \
  -v sha_termos="'$(sha termos-de-uso)'" \
  -v sha_contrato="'$(sha contrato-saas)'" \
  -v sha_dpa="'$(sha acordo-tratamento-dados)'" \
  -f "$here/tests.sql" 2>&1 | sed -e 's/^psql:[^ ]* //' -e 's/^NOTICE:  //'
[ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
echo "verify-school-agreements: todos os testes passaram"

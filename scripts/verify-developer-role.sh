#!/usr/bin/env bash
# Testes do papel developer (migration 20261111233000) num Postgres local
# descartável. Nunca toca o banco publicado.
# Uso: scripts/verify-developer-role.sh   (precisa de initdb/pg_ctl/psql 15+;
# rode como usuário comum, não root)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mig="$root/appmistakemap/database/supabase/migrations"
bin="${PG_BIN:-$(dirname "$(command -v initdb 2>/dev/null || ls /usr/lib/postgresql/*/bin/initdb | tail -1)")}"
tmp="$(mktemp -d)"
port="${PG_TEST_PORT:-55434}"
cleanup() { "$bin/pg_ctl" -D "$tmp/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$tmp"; }
trap cleanup EXIT
"$bin/initdb" -D "$tmp/data" -U postgres -A trust >/dev/null
"$bin/pg_ctl" -D "$tmp/data" -o "-p $port -k $tmp -c listen_addresses=''" -l "$tmp/log" start >/dev/null
run() { psql -h "$tmp" -p "$port" -U postgres -d postgres -v ON_ERROR_STOP=1 -q "$@"; }
run -f "$root/scripts/schools_rls/supabase_stub.sql"
sed 's/^create extension if not exists "pgcrypto" with schema extensions;//I' \
  "$mig/20260901163259_create_initial_schema.sql" | run
for m in 20260901173121_create_profiles 20260928194109_add_role_admin_system 20260929112200_fix_profiles_rls_recursion \
         20261109221500_fix_user_manage_own_profile_recursion 20261111233000_developer_role; do
  run -f "$mig/$m.sql"
done
# No Supabase, as tabelas de public nascem com grant para authenticated.
run -c "grant select, insert, update, delete on all tables in schema public to authenticated"
run -o /dev/null -f "$root/scripts/developer_role/tests.sql" 2>&1 | sed -e 's/^psql:[^ ]* //' -e 's/^NOTICE:  //'
[ "${PIPESTATUS[0]}" -eq 0 ] || exit 1
echo "verify-developer-role: todos os testes passaram"

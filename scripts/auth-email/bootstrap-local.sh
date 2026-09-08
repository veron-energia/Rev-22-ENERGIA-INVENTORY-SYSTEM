#!/bin/sh
# Bring up a disposable Postgres for the Auth-email migration tests.
#
#   scripts/auth-email/bootstrap-local.sh          # start (creates if needed)
#   scripts/auth-email/bootstrap-local.sh stop     # stop
#   scripts/auth-email/bootstrap-local.sh destroy  # stop and delete the datadir
#
# Everything lives under AUTH_EMAIL_PGDATA (default: a temp dir), on port 55442,
# with its own database. It never touches production and never touches the
# invoice work's cluster on 55441.
set -eu

PORT=55442
DB=energia_auth_email_test
PGDATA_DIR="${AUTH_EMAIL_PGDATA:-${TMPDIR:-/tmp}/energia-auth-email-pg}"
BIN="$(dirname "$(command -v pg_ctl)")"

start() {
  if [ ! -d "$PGDATA_DIR/base" ]; then
    echo "initdb -> $PGDATA_DIR"
    "$BIN/initdb" -D "$PGDATA_DIR" -U postgres --auth=trust >/dev/null
  fi
  if "$BIN/pg_ctl" -D "$PGDATA_DIR" status >/dev/null 2>&1; then
    echo "already running on $PORT"
  else
    "$BIN/pg_ctl" -D "$PGDATA_DIR" -o "-p $PORT -k /tmp -c listen_addresses=''" -w start >/dev/null
    echo "started on $PORT"
  fi
  PGHOST=/tmp PGPORT=$PORT PGUSER=postgres "$BIN/psql" -X -tAc \
    "select 1 from pg_database where datname='$DB'" postgres | grep -q 1 || \
    PGHOST=/tmp PGPORT=$PORT PGUSER=postgres "$BIN/createdb" "$DB"

  # The bits of a Supabase project that migration 200 leans on, and nothing else:
  # the three API roles and a minimal auth.users. This is a stand-in for schema
  # owned by the platform, not a copy of it.
  PGHOST=/tmp PGPORT=$PORT PGUSER=postgres "$BIN/psql" -X -q -v ON_ERROR_STOP=1 -d "$DB" <<'SQL'
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon')          then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname='service_role')  then create role service_role nologin bypassrls; end if;
end $$;
create schema if not exists auth;
create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  email_confirmed_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);
SQL
  echo "database $DB ready"
}

case "${1:-start}" in
  start)   start ;;
  stop)    "$BIN/pg_ctl" -D "$PGDATA_DIR" -m fast stop >/dev/null 2>&1 || true; echo stopped ;;
  destroy) "$BIN/pg_ctl" -D "$PGDATA_DIR" -m fast stop >/dev/null 2>&1 || true; rm -rf "$PGDATA_DIR"; echo destroyed ;;
  *) echo "usage: $0 [start|stop|destroy]" >&2; exit 2 ;;
esac

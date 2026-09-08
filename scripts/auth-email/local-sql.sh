#!/bin/sh
# Fixed disposable target for the Auth-email work. No production connection
# option exists here on purpose. Port 55442 is deliberately distinct from the
# invoice work's 55441 so the two isolated databases never collide.
export PGHOST=/tmp PGPORT=55442 PGUSER=postgres PGDATABASE=energia_auth_email_test
exec psql -X -v ON_ERROR_STOP=1 "$@"

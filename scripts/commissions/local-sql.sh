#!/bin/sh
export PGHOST=/tmp PGPORT=55444 PGUSER=postgres PGDATABASE=energia_commission_test
exec psql -X -v ON_ERROR_STOP=1 "$@"

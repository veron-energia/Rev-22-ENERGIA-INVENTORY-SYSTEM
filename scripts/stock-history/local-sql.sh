#!/bin/sh
export PGHOST=/tmp PGPORT=55443 PGUSER=postgres PGDATABASE=energia_stock_history_test
exec psql -X -v ON_ERROR_STOP=1 "$@"

#!/bin/sh
export PGHOST=/tmp PGPORT=55445 PGUSER=postgres PGDATABASE=energia_invoice_date_test
exec psql -X -v ON_ERROR_STOP=1 "$@"

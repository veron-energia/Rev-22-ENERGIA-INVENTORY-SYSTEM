#!/bin/sh
# Disposable targets only. ENERGIA_INVOICE_DB may select the combined-history
# integration database, and nothing else: the name is checked against a fixed
# allowlist rather than passed through, so this helper still has no way to reach
# production.
DB="${ENERGIA_INVOICE_DB:-energia_invoice_test}"
case "$DB" in
  energia_invoice_test|energia_integration_test) ;;
  *) echo "Refusing database '$DB'; only the disposable invoice and integration databases are allowed." >&2; exit 1 ;;
esac
export PGHOST=/tmp PGPORT=55441 PGUSER=postgres PGDATABASE="$DB"
exec psql -X -v ON_ERROR_STOP=1 "$@"

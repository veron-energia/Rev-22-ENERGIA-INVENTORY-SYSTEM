#!/bin/sh
set -eu
export PGHOST=/tmp PGPORT=55445 PGUSER=postgres PGDATABASE=energia_invoice_date_test
python3 scripts/invoice-dates/bootstrap-local.py > .invoice-date-test/bootstrap.log
scripts/invoice-dates/local-sql.sh -q -f scripts/invoice-dates/tests/regression.sql -f scripts/invoice-dates/tests/evidence-edge-cases.sql
# Retain upstream tests unchanged; extend their rich, rolled-back fixtures.
python3 - <<'PY'
from pathlib import Path
extra=Path('scripts/invoice-dates/tests/operational-roundtrip.sql').read_text()
for source,name in [('scripts/invoices/regression.sql','invoice'),('scripts/commissions/tests/invoice-adjustments.sql','commission')]:
    text=Path(source).read_text()
    assert text.count('rollback;')==1
    Path(f'.invoice-date-test/{name}-integrity.sql').write_text(text.replace('rollback;',extra+'\nrollback;'))
PY
scripts/invoice-dates/local-sql.sh -q -f .invoice-date-test/invoice-integrity.sql -f .invoice-date-test/commission-integrity.sql -f scripts/commissions/tests/regression.sql -f scripts/invoices/tests/commission-refund-basis.sql
node scripts/invoice-dates/tests/concurrency.mjs

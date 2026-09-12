#!/bin/sh
# Recreates ONLY the dedicated disposable fixture. bootstrap checks the exact
# database, socket, port AND project-owned data directory before any DDL.
set -eu
export PGHOST=/tmp PGPORT=55444 PGUSER=postgres PGDATABASE=energia_commission_test
python3 scripts/commissions/bootstrap-local.py --through 272 > .commission-test/bootstrap.log
scripts/commissions/local-sql.sh -q -f scripts/commissions/tests/legacy-seed.sql
scripts/commissions/local-sql.sh -qAt -f scripts/commissions/review-payouts.sql > .commission-test/legacy-review-before.json
python3 scripts/commissions/build-migration-bundle.py > .commission-test/deploy-280-282.sql
scripts/commissions/local-sql.sh -q -f .commission-test/deploy-280-282.sql
# Historical compatibility, deliberately pinned: these check the legacy payout
# backfill exactly as it lands on a 272-era database plus the 280-282 bundle.
scripts/commissions/local-sql.sh -q -f scripts/commissions/tests/legacy-check.sql

# Current integration tests need the CURRENT schema. 280-282 are already on
# this fixture via the deployment bundle above, so the upgrade starts at 290.
# Upgrading the same fixture
# to the complete migration set (rather than pinning it at 272) is why
# scripts/invoices/regression.sql used to fail here: it has expected 292's
# payment-date rule since 292 landed, while this runner stopped at 272.
python3 scripts/commissions/bootstrap-local.py --from 290 --no-reset >> .commission-test/bootstrap.log
scripts/commissions/local-sql.sh -q -f scripts/commissions/tests/regression.sql -f scripts/commissions/tests/invoice-adjustments.sql -f scripts/invoices/tests/commission-refund-basis.sql -f scripts/invoices/regression.sql
node scripts/commissions/tests/concurrency.mjs
scripts/commissions/local-sql.sh -qAt -f scripts/commissions/review-payouts-after.sql > .commission-test/review-after.json
scripts/commissions/local-sql.sh -q -f scripts/commissions/verify-install.sql > .commission-test/verification.txt

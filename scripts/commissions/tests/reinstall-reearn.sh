#!/bin/sh
# 334 and the re-earn script, end to end, on the disposable commission fixture.
#
# The fixture must already be bootstrapped (scripts/commissions/tests/run-local.sh
# or bootstrap-local.py). The 5D2-era earn_invoice_commission is installed
# first, straight from file 19, so the database looks the way production did;
# then 334 twice (the second must be a no-op), then the re-earn script three
# times: a rehearsal that must change nothing, the real run, and a second real
# run that must find nothing left to do.
set -eu
export PGHOST=/tmp PGPORT=55444 PGUSER=postgres PGDATABASE=energia_commission_test
SQL="scripts/commissions/local-sql.sh -q"
OUT=.commission-test
MD5="select md5(pg_get_functiondef('public.earn_invoice_commission(uuid)'::regprocedure))"

# 0. Whatever a previous run left behind, start from the repository's build
#    and a clean slate.
$SQL -f supabase/334_commission_functions_reinstalled.sql
$SQL -f scripts/commissions/tests/reinstall-reearn-cleanup.sql
canonical=$($SQL -Atc "$MD5")

# 1. Production's build.
sed -n '/^create or replace function public.earn_invoice_commission/,/^end; \$\$;/p' \
  supabase/19_phase5d2_promotion_sales.sql | $SQL
old=$($SQL -Atc "$MD5")
[ "$old" != "$canonical" ] || { echo "the 5D2 body was not installed"; exit 1; }

# 2. Fixtures written by that build.
$SQL -f scripts/commissions/tests/reinstall-reearn-fixture.sql > $OUT/reearn-fixture.txt

# 3. 334, twice.
$SQL -f supabase/334_commission_functions_reinstalled.sql
[ "$($SQL -Atc "$MD5")" = "$canonical" ] || { echo "334 did not restore the canonical earn_invoice_commission"; exit 1; }
$SQL -f supabase/334_commission_functions_reinstalled.sql
[ "$($SQL -Atc "$MD5")" = "$canonical" ] || { echo "334 is not idempotent"; exit 1; }

# 4. Rehearsal, real run, second real run.
$SQL -f scripts/commissions/reearn-affiliate-commissions.sql > $OUT/reearn-dry.txt 2>&1
grep -q 'DRY RUN: nothing was changed' $OUT/reearn-dry.txt
$SQL -v phase=dry -f scripts/commissions/tests/reinstall-reearn-check.sql

$SQL -v apply=yes -f scripts/commissions/reearn-affiliate-commissions.sql > $OUT/reearn-apply.txt 2>&1
grep -q 'APPLYING' $OUT/reearn-apply.txt
$SQL -v phase=applied -f scripts/commissions/tests/reinstall-reearn-check.sql

rows=$($SQL -Atc "select count(*) from public.commissions x join public.invoices i on i.id = x.invoice_id where i.invoice_no like 'REEARN-%'")
$SQL -v apply=yes -f scripts/commissions/reearn-affiliate-commissions.sql > $OUT/reearn-again.txt 2>&1
$SQL -v phase=again -v rows=$rows -f scripts/commissions/tests/reinstall-reearn-check.sql

# 5. Leave the fixture as it was found.
$SQL -f scripts/commissions/tests/reinstall-reearn-cleanup.sql
echo "reinstall + re-earn: ok"

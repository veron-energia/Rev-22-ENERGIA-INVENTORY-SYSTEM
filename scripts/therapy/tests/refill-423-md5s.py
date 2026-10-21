#!/usr/bin/env python3
"""Refill the AFTER md5s of supabase/423_vouchers_services_prices_and_splits.sql.

Run the migration once on a test database (inside a rolled-back transaction).
When a text it builds is not the one recorded, it stops with a message that
lists each function and the md5 it built:

    423: a text built is not the tested one: trg_audit_voucher_change() built 0123...; ...

Paste that message into this script's standard input. It writes each md5 into
the migration's constant and into the AFTER list of the header. Then run the
migration again: it must install and pass its own checks.

    python3 scripts/therapy/tests/refill-423-md5s.py < message.txt

Only use this after re-reading the BEFORE texts from production and re-testing:
an md5 only says "this is the text that was tested".
"""
import re, sys
from pathlib import Path

MIG = Path(__file__).resolve().parents[3] / 'supabase/423_vouchers_services_prices_and_splits.sql'
NAMES = {
    'trg_audit_voucher_change()': 'c_audit_after',
    'soft_delete_voucher(uuid,text,boolean)': 'c_softdel_after',
    'set_therapy_service_stores(uuid,jsonb)': 'c_stores_after',
    'set_voucher_price_all_stores(uuid,numeric,boolean)': 'c_vpall_after',
    'set_voucher_prices(uuid,uuid,numeric,numeric,boolean)': 'c_vp_after',
    'upsert_therapy_service(uuid,text,text,numeric,integer,text,integer,numeric,text,boolean,text)': 'c_svc_after',
    'upsert_therapy_closure_date(uuid,date,text,text,text,text,date,text,text,text)': 'c_cl_after',
    'set_unlimited_therapy_price(uuid,uuid,numeric,numeric,boolean)': 'c_ut_after',
    'create_split_credit_package_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid)': 'c_cp_after',
    'create_split_premium_bundle_invoices(uuid,uuid,jsonb,uuid[],uuid,text,uuid)': 'c_pb_after',
}
MD5 = r'(?:[0-9a-f]{32}|@AFTER_[A-Z]+@)'

found = dict(re.findall(r'([a-z_]+\([^)]*\)) built ([0-9a-f]{32})', sys.stdin.read()))
if not found:
    sys.exit('No "<function> built <md5>" pairs in the input.')
text = MIG.read_text()
for fn, md5 in found.items():
    const = NAMES.get(fn) or sys.exit(f'Unknown function in the message: {fn}')
    # The constant in the DO block: it names the old value, which the header
    # AFTER list carries too.
    m = re.search(rf"{const}\s+constant text := '({MD5})'", text)
    if not m:
        sys.exit(f'{const} is not in the migration')
    old = m.group(1)
    head, after = text.split('-- AFTER (for later guards):', 1)
    after_head, rest = after.split('\n\n', 1)
    if after_head.count(old) != 1 or text.count(m.group(0)) != 1:
        sys.exit(f'{fn}: the old value {old} is not once in the header and once in the constant')
    after_head = after_head.replace(old, md5)
    text = head + '-- AFTER (for later guards):' + after_head + '\n\n' + rest
    text = text.replace(m.group(0), m.group(0).replace(old, md5))
MIG.write_text(text)
print(f'Filled {len(found)} md5(s) in {MIG.name}.')

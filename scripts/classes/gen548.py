#!/usr/bin/env python3
"""Rebuild 548's pins after any change to its function texts (the migration pins the md5 of every function
it adds, and the function fingerprint after, in its header, its c_new array and c_fp_after; the UNDO pins
the same md5s).

It runs the migration's own DDL blocks (the tables and the nine functions) in a rolled-back transaction on a
scratch copy of production after 549 (default database m548_gen on 127.0.0.1:54396; make it with
`createdb -T <a copy of production after 549>`; it never writes), reads each new function's
md5(pg_get_functiondef) and the fingerprint of public's functions, and writes them into
supabase/548_class_page_for_the_four_class_vouchers.sql and scripts/classes/undo-548.sql.

  python3 scripts/classes/gen548.py            # rewrite the pins in place
  GEN_DB=other_db python3 scripts/classes/gen548.py

Mutation checks: copy the migration, change one rule in the copy, run this with SRC_SQL=<copy> OUT_SQL=<new copy> (the UNDO is left alone),
then run the suite with -v mig=<copy> and see that the rule's check fails.
On another base (549's, say): also SRC_UNDO=<undo copy> OUT_UNDO=<new undo copy> and GEN_DB=<a scratch copy of that base>.
"""
import os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_SQL = os.path.join(HERE, '..', '..', 'supabase', '548_class_page_for_the_four_class_vouchers.sql')
SQL = os.environ.get('OUT_SQL') or REPO_SQL
SRC = os.environ.get('SRC_SQL') or REPO_SQL
UND = os.path.join(HERE, 'undo-548.sql')
DB = os.environ.get('GEN_DB', 'm548_gen')
SIGS = ['class_line_units(uuid)', 'class_live_seats(uuid)', 'trg_class_seat_date_capacity()', 'class_page_data()',
        'class_choose_date(uuid,integer,uuid)', 'class_set_attendance(uuid,uuid,integer,boolean)',
        'class_save_session(uuid,uuid,jsonb)', 'class_remove_session(uuid)', 'class_save_details(uuid,jsonb)',
        'trg_class_line_changed()']

text = open(SRC).read()
blocks = re.findall(r'execute \$ddl\$(.*?)\$ddl\$;', text, re.S)
assert len(blocks) == 3, len(blocks)
q = 'begin;\n' + '\n'.join(blocks) + '\n'
for s in SIGS:
    q += "select 'PIN|%s|' || md5(pg_get_functiondef(to_regprocedure('public.%s')));\n" % (s, s)
q += ("select 'FP|' || md5(string_agg(md5(pg_get_functiondef(oid)), '' order by oid::regprocedure::text)) || '/' || count(*) "
      "from pg_proc where pronamespace='public'::regnamespace and prokind='f';\nrollback;\n")
env = dict(os.environ, PGPASSWORD='postgres')
r = subprocess.run(['psql', '-h', '127.0.0.1', '-p', '54396', '-U', 'postgres', '-d', DB, '-X', '-Atq', '-v', 'ON_ERROR_STOP=1'],
                   input=q, capture_output=True, text=True, env=env)
if r.returncode != 0:
    print(r.stderr); sys.exit(1)
pins, fp = {}, None
for line in r.stdout.splitlines():
    if line.startswith('PIN|'):
        _, s, m = line.split('|'); pins[s] = m
    elif line.startswith('FP|'):
        fp = line[3:]
assert len(pins) == len(SIGS) and fp

doc = '\n'.join('--   %-70s %s' % (s, pins[s]) for s in SIGS)
arr = ',\n'.join("    ['%s', '%s']" % (s, pins[s]) for s in SIGS)

def repin(t, with_header):
    # the c_new array
    t = re.sub(r"(c_new constant text\[\]\[\] := array\[\n)(?:    \['[^']+', '[0-9a-f]{32}'\],?\n)+(  \];)", lambda m: m.group(1) + arr + '\n' + m.group(2), t)
    if with_header:
        t = re.sub(r"(-- NEW \(AFTER; md5 of pg_get_functiondef\):\n)(?:--   [a-z_]+\([a-z,]*\) +[0-9a-f]{32}\n)+", lambda m: m.group(1) + doc + '\n', t)
        t = re.sub(r"(c_fp_after constant text := ')[0-9a-f]{32}/\d+(')", lambda m: m.group(1) + fp + m.group(2), t)
        t = re.sub(r"(after: )[0-9a-f]{32}/\d+(\.)", lambda m: m.group(1) + fp + m.group(2), t, count=1)
    return t

out = repin(text, True)
open(SQL, 'w').write(out)
if not os.environ.get('OUT_SQL'):
    u = open(UND).read()
    open(UND, 'w').write(repin(u, False))
elif os.environ.get('SRC_UNDO') and os.environ.get('OUT_UNDO'):
    open(os.environ['OUT_UNDO'], 'w').write(repin(open(os.environ['SRC_UNDO']).read(), False))
print(fp)
for s in SIGS:
    print(s, pins[s])

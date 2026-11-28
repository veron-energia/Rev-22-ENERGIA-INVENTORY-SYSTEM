#!/usr/bin/env python3
"""548: the capacity cannot be raced (two real connections, one statement each, a pg_sleep between).

A date holds 5 of 6 seats. Scenario 1: a seat takes the 6th place (its trigger holds the date's row, then
sleeps before it commits) while an Owner lowers the limit to 5: class_save_details must wait for the seat and
then refuse (the date has 6). Scenario 2: the Owner lowers the limit to 5 (holding the dates, then sleeping
before it commits) while a seat asks for the 6th place: it must wait and then be told the date is full (5 of
5). Either order leaves at most `limit` seats on the date.

It builds its own committed database m548_race from a copy of production after 549 that has no class tables
(default m548_base; never touches another database), installs 548 (the file given, default the repo's) and the
suite's fixtures, runs the two scenarios and drops the database. Exit 0 = both hold.

  python3 scripts/classes/tests/race548.py [path-to-548.sql]
"""
import os, re, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
MIG = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(REPO, 'supabase', '548_class_page_for_the_four_class_vouchers.sql')
TEMPLATE = os.environ.get('RACE_TEMPLATE', 'm548_b549')
DB = 'm548_race'
ENV = dict(os.environ, PGPASSWORD='postgres')
BASE = ['psql', '-h', '127.0.0.1', '-p', '54396', '-U', 'postgres', '-X', '-q', '-t', '-A']


def psql(db, *args, stdin=None):
    return subprocess.run(BASE + ['-d', db] + list(args), input=stdin, capture_output=True, text=True, env=ENV)


psql('postgres', '-c', f'drop database if exists {DB}')
r = psql('postgres', '-c', f'create database {DB} template {TEMPLATE}')
if r.returncode:
    print(r.stderr); sys.exit(2)
try:
    suite = open(os.path.join(HERE, 'class-page-548.sql')).read()
    head = suite[:suite.index('-- ═════ B Who bought ═════')]
    head = head.replace('\\ir :mig', '\\ir ' + MIG).replace('\\ir ../../../supabase', '\\ir ' + os.path.join(REPO, 'supabase'))
    head += """
create table public.race_ids as
  select 'l_a_skin1' k, :'l_a_skin1'::uuid v union all select 'l_a_skin2', :'l_a_skin2'::uuid union all select 'l_b_skin1', :'l_b_skin1'::uuid
  union all select 'l_b_skin2', :'l_b_skin2'::uuid union all select 'sk_mar', pg_temp.session_id('KPopClass','2027-03-24')
  union all select 'v_skin', pg_temp.fx('v_KPopClass') union all select 'owner', pg_temp.fx('owner');
commit;
"""
    with tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False) as f:
        f.write(head); fixture = f.name
    r = psql(DB, '-v', 'ON_ERROR_STOP=1', '-f', fixture)
    if r.returncode:
        print('fixture failed:', r.stderr[-600:]); sys.exit(2)

    def one(sql):
        return psql(DB, '-c', sql).stdout.strip()
    ID = lambda k: f"(select v from race_ids where k='{k}')"
    CLAIM = f"select set_config('request.jwt.claim.sub', {ID('owner')}::text, %s) \\g /dev/null\n"
    choose = lambda line, seat: f"select public.class_choose_date({ID(line)}, {seat}, {ID('sk_mar')})::text;"
    prefill = CLAIM % 'false' + '\n'.join(choose(l, n) for l, n in [('l_a_skin2', 1), ('l_a_skin2', 2), ('l_a_skin2', 3), ('l_b_skin1', 1), ('l_b_skin2', 1)])
    r = psql(DB, '-v', 'ON_ERROR_STOP=1', stdin=prefill)
    if r.returncode:
        print('prefill failed:', r.stderr[-400:]); sys.exit(2)
    seats = lambda: int(one(f"select count(*) from class_seat_dates where session_id = {ID('sk_mar')}"))
    cap = lambda: int(one(f"select capacity_per_date from class_vouchers where voucher_id = {ID('v_skin')}"))
    assert seats() == 5 and cap() == 6, (seats(), cap())
    lower = f"select public.class_save_details({ID('v_skin')}, '{{\"capacity_per_date\":5}}')::text;"
    sleep = 'select pg_sleep(3) \\g /dev/null\n'
    ok = True

    def two(first, second):
        """first runs (and sleeps in its transaction); second starts one second later. Returns (first rc, second rc, second message)."""
        a = subprocess.Popen(BASE + ['-d', DB, '-v', 'ON_ERROR_STOP=1'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=ENV)
        a.stdin.write(first); a.stdin.close()
        time.sleep(1)
        t0 = time.time()
        rb = psql(DB, '-v', 'ON_ERROR_STOP=1', stdin=second)
        waited = time.time() - t0
        a.wait()
        return a.returncode, rb.returncode, rb.stderr.strip().splitlines()[:1], waited

    # Scenario 1: the seat first, the limit change second.
    s1 = 'begin;\n' + CLAIM % 'true' + choose('l_a_skin1', 1) + '\n' + sleep + 'commit;\n'
    s2 = CLAIM % 'false' + lower + '\n'
    rc1, rc2, msg, waited = two(s1, s2)
    good = rc1 == 0 and rc2 != 0 and seats() == 6 and cap() == 6 and waited > 1.5
    print(f"scenario 1 (a seat takes the 6th place, the limit is lowered meanwhile): seat rc={rc1}, limit change rc={rc2} {msg}, waited {waited:.1f}s, seats={seats()}, limit={cap()} -> {'ok' if good else 'FAIL'}")
    ok &= good
    # reset
    psql(DB, '-c', f"delete from class_seat_dates where invoice_item_id = {ID('l_a_skin1')}")
    psql(DB, '-c', f"update class_vouchers set capacity_per_date = 6 where voucher_id = {ID('v_skin')}")
    assert seats() == 5 and cap() == 6
    # Scenario 2: the limit change first, the seat second.
    s1 = 'begin;\n' + CLAIM % 'true' + lower + '\n' + sleep + 'commit;\n'
    s2 = CLAIM % 'false' + choose('l_a_skin1', 1) + '\n'
    rc1, rc2, msg, waited = two(s1, s2)
    good = rc1 == 0 and rc2 != 0 and seats() == 5 and cap() == 5 and waited > 1.5
    print(f"scenario 2 (the limit is lowered, a seat asks for the 6th place meanwhile): limit change rc={rc1}, seat rc={rc2} {msg}, waited {waited:.1f}s, seats={seats()}, limit={cap()} -> {'ok' if good else 'FAIL'}")
    ok &= good
finally:
    psql('postgres', '-c', f'drop database if exists {DB}')
print('RACE OK' if ok else 'RACE FAILED')
sys.exit(0 if ok else 1)

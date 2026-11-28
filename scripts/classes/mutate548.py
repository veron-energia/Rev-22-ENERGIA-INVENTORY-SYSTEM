#!/usr/bin/env python3
"""Mutation checks for 548 (the Class page): one rule at a time is changed in a copy of the migration, the pins
are rebuilt (gen548.py), the suite scripts/classes/tests/class-page-548.sql is run with that copy and the
targeted check must fail (or the migration must refuse itself). Needs a copy of production after 549 holding no
class tables (default m548_t1) and the scratch database gen548.py uses (m548_gen).

  python3 scripts/classes/mutate548.py [M1 M4 ...]      # all mutants, or the named ones
  MUT_DB=other_db python3 scripts/classes/mutate548.py
"""
import os, subprocess, sys, re, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
SQLF = os.path.join(REPO, 'supabase', '548_class_page_for_the_four_class_vouchers.sql')
DB = os.environ.get('MUT_DB', 'm548_t1')
tpl = open(SQLF).read()
M = [
 ('M1 capacity off by one (> instead of >=)', "if v_taken >= v_cap then", "if v_taken > v_cap then", 'C7'),
 ('M2 refunded units not taken off', "else least(it.quantity, floor(round(x.refunded * it.quantity / x.paid, 6)))::integer end, 0)", "else 0 end, 0)", 'B10'),
 ('M3 cancelled invoices still give seats', "and i.status in ('unpaid', 'partially_paid', 'paid', 'completed_foc', 'cancellation_requested', 'refund_requested')", "and true", 'B12'),
 ('M4 staff may edit dates', "perform public.require_active_staff('{owner,manager}');\n      -- 548 (the Owner, 27 Nov 2026): only Owners and Managers add or change a class's dates.", "perform public.require_active_staff('{owner,manager,staff}');\n      -- 548 (the Owner, 27 Nov 2026): only Owners and Managers add or change a class's dates.", 'E1'),
 ('M5 staff of any store may choose a date', "if not public.user_has_store_access(inv.store_id) then\n        raise exception 'That seat is on an invoice of a store you do not work at.' using errcode = '42501'; end if;\n      select * into c from public.class_vouchers where voucher_id = it.voucher_id;", "select * into c from public.class_vouchers where voucher_id = it.voucher_id;", 'C2'),
 ('M6 page shows every store to everyone', "where public.user_has_store_access(i.store_id)), '[]'::jsonb))", "where true), '[]'::jsonb))", 'B2'),
 ('M18 a Manager sees every store (the old reading)', "where public.user_has_store_access(i.store_id)), '[]'::jsonb))", "where public.is_owner_or_manager() or public.user_has_store_access(i.store_id)), '[]'::jsonb))", 'B1b'),
 ('M19 a Manager may tick another store seat', "if not public.user_has_store_access(inv.store_id) then\n        raise exception 'That seat is on an invoice of a store you do not work at.' using errcode = '42501'; end if;\n      select * into c from public.class_vouchers where voucher_id = s.voucher_id;", "if not (public.is_owner_or_manager() or public.user_has_store_access(inv.store_id)) then\n        raise exception 'That seat is on an invoice of a store you do not work at.' using errcode = '42501'; end if;\n      select * into c from public.class_vouchers where voucher_id = s.voucher_id;", 'A3'),
 ('M7 capacity counts cancelled seats too', "join public.class_live_seats(v_vid) ls on ls.invoice_item_id = d.invoice_item_id and ls.seat_no = d.seat_no\n         where d.session_id = new.session_id", "join public.invoice_items ls on ls.id = d.invoice_item_id\n         where d.session_id = new.session_id", 'C12'),
 ('M8 Inventory Manager may open the page', "perform public.require_active_staff();\n      perform public.inventory_manager_guard('classes');\n      -- 548 (the Owner, 27 Nov 2026): the Class page.", "perform public.require_active_staff();\n      -- 548 (the Owner, 27 Nov 2026): the Class page.", 'B7'),
 ('M9 old lines not frozen before the rename', "with f as (update public.invoice_items set item_name_snapshot = c_codes[k][2]\n                  where voucher_id = v_id and line_kind = 'voucher' and nullif(btrim(item_name_snapshot), '') is null\n                  returning id)", "with f as (update public.invoice_items set item_name_snapshot = c_codes[k][2]\n                  where false returning id)", 'N4'),
 ('M10 a choose-a-date seat may be ticked on any date', "if v_chosen is distinct from p_session_id then\n          raise exception 'This seat chose another date (or none yet): set its date first.'; end if;", "null;", 'A2'),
 ('M11 a date with a tick may be changed', "if v_old is not null and exists (select 1 from public.class_attendance\n                                        where invoice_item_id = it.id and seat_no = p_seat_no and session_id = v_old) then\n        raise exception 'This seat is ticked as attended on its date. Remove the tick first.'; end if;", "null;", 'A6'),
 ('M12 a date a live seat chose may be removed', "      if exists (select 1 from public.class_seat_dates d\n                   join public.class_live_seats(s.voucher_id) ls on ls.invoice_item_id = d.invoice_item_id and ls.seat_no = d.seat_no\n                  where d.session_id = s.id) then", "      if false then", 'E9'),
 ('M13 capacity may drop below what a date holds', "if v_cap is not null and v_cap < v_max then", "if false then", 'E14'),
 ('M15 Admin may remove a date', "perform public.require_active_staff('{owner,manager}');\n      -- 548: only Owners and Managers remove a date", "perform public.require_active_staff('{owner,manager,admin}');\n      -- 548: only Owners and Managers remove a date", 'E8'),
 ('M16 anon may call the page functions', "public.class_remove_session(uuid), public.class_save_details(uuid, jsonb) from public, anon;", "public.class_remove_session(uuid), public.class_save_details(uuid, jsonb) from public;", 'I4'),
 ('M17 a login may write the tables', "grant select on table public.class_vouchers, public.class_sessions, public.class_seat_dates, public.class_attendance to authenticated;", "grant select, insert, update, delete on table public.class_vouchers, public.class_sessions, public.class_seat_dates, public.class_attendance to authenticated;", 'I3'),
 ('M20 the line trigger deletes nothing', "        delete from public.class_attendance where invoice_item_id = old.id;\n        delete from public.class_seat_dates where invoice_item_id = old.id;\n", "        null;\n", 'L1'),
 ('M21 the update trigger fires without a change of voucher', "for each row when (old.voucher_id is distinct from new.voucher_id) execute function", "for each row execute function", 'L4'),
 ('M22 a changed line writes no entry', "perform public.write_audit_ex('invoice_items', old.id, 'class_seats_cleared',\n          jsonb_build_object('voucher_id', old.voucher_id, 'seat_dates', v_dates, 'ticks', v_ticks),\n          jsonb_build_object('voucher_id', new.voucher_id)", "perform public.write_audit_ex('invoice_items', old.id, 'class_seats_not_logged',\n          jsonb_build_object('voucher_id', old.voucher_id, 'seat_dates', v_dates, 'ticks', v_ticks),\n          jsonb_build_object('voucher_id', new.voucher_id)", 'L1'),
 ('M23 a removed line writes no entry', "      perform public.write_audit_ex('invoice_items', old.id, 'class_seats_cleared',\n        jsonb_build_object('voucher_id', old.voucher_id, 'seat_dates', v_dates, 'ticks', v_ticks),\n        jsonb_build_object('removed', true)", "      perform public.write_audit_ex('invoice_items', old.id, 'class_seats_not_logged',\n        jsonb_build_object('voucher_id', old.voucher_id, 'seat_dates', v_dates, 'ticks', v_ticks),\n        jsonb_build_object('removed', true)", 'L3'),
 ('M24 remove_session back to the old rule', "      if exists (select 1 from public.class_seat_dates d\n                   join public.class_live_seats(s.voucher_id) ls on ls.invoice_item_id = d.invoice_item_id and ls.seat_no = d.seat_no\n                  where d.session_id = s.id) then", "      if exists (select 1 from public.class_seat_dates d where d.session_id = s.id) then", 'L5b'),
 ('M25 remove_session ignores ticks', "if exists (select 1 from public.class_attendance where session_id = s.id) then\n        raise exception 'Someone was ticked", "if false then\n        raise exception 'Someone was ticked", 'L5d'),
 ('M26 remove_session does not list the cleared dates', "to_jsonb(s) || jsonb_build_object('cleared_seat_dates', v_cleared), null", "to_jsonb(s), null", 'L5c'),
 ('M27 the closing name check widened back to all four vouchers', "it.voucher_id in (v_foundation, v_advanced, v_skin)\n", "it.voucher_id in (v_foundation, v_advanced, v_skin, v_lc)\n", 'N7'),
 ('M28 the freeze skipped for one renamed voucher (Foundation)', "where voucher_id = v_id and line_kind = 'voucher' and nullif(btrim(item_name_snapshot), '') is null", "where voucher_id = v_id and c_codes[k][1] <> 'EmiLymphatic' and line_kind = 'voucher' and nullif(btrim(item_name_snapshot), '') is null", 'N9'),
 ('M14 the capacity of 6 is not seeded', "'choose_date', '6', '3']", "'choose_date', '', '3']", 'S6'),
]
only = sys.argv[1:]
tmp = tempfile.mkdtemp()
env0 = dict(os.environ, PGPASSWORD='postgres')
for name, a, b, expect in M:
    tag = name.split()[0]
    if only and tag not in only: continue
    if tpl.count(a) != 1:
        print(tag, 'ANCHOR FOUND', tpl.count(a), 'TIMES'); continue
    src = os.path.join(tmp, 'mut_%s_src.sql' % tag)
    out = os.path.join(tmp, 'mut_%s.sql' % tag)
    open(src, 'w').write(tpl.replace(a, b))
    r = subprocess.run(['python3', os.path.join(HERE, 'gen548.py')], env=dict(os.environ, SRC_SQL=src, OUT_SQL=out), capture_output=True, text=True)
    if r.returncode: print(tag, 'GEN FAILED', r.stderr[-300:]); continue
    r = subprocess.run(['psql', '-h', '127.0.0.1', '-p', '54396', '-U', 'postgres', '-d', DB, '-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1',
                        '-v', 'mig=' + out, '-f', os.path.join(HERE, 'tests', 'class-page-548.sql')], capture_output=True, text=True, env=env0)
    o = r.stdout + r.stderr
    fails = re.findall(r'FAIL ([A-Z]\d+[a-z]?) ', o)
    refused = 'ERROR:  548:' in o
    caught = expect in fails or (refused and expect not in fails)
    if refused and expect not in fails:
        fails = ['(the migration refused itself: %s)' % re.findall(r'ERROR:  548: ([^\n]{0,70})', o)[0]]
    print('%-3s %-55s expect %-4s %s  failing: %s' % (tag, name.split(' ', 1)[1], expect, 'CAUGHT' if caught else 'NOT CAUGHT', ' '.join(dict.fromkeys(fails))[:150]))

# The limit race (two real connections): the mutants below must make scripts/classes/tests/race548.py fail.
RACE = [
 ('R1 class_save_details does not lock the dates before counting', "        perform 1 from public.class_sessions where voucher_id = p_voucher_id for update;\n", ""),
 ('R2 the capacity trigger reads the limit in the same statement as the lock', "select s.voucher_id into v_vid from public.class_sessions s where s.id = new.session_id for update of s;", "select s.voucher_id, c.capacity_per_date, c.seat_mode into v_vid, v_cap, v_mode from public.class_sessions s join public.class_vouchers c on c.voucher_id = s.voucher_id where s.id = new.session_id for update of s;"),
]
if not only or any(t.startswith('R') for t in only):
    for name, a, b in RACE:
        tag = name.split()[0]
        if only and tag not in only: continue
        if tpl.count(a) != 1:
            print(tag, 'ANCHOR FOUND', tpl.count(a), 'TIMES'); continue
        src = os.path.join(tmp, 'mut_%s_src.sql' % tag)
        out = os.path.join(tmp, 'mut_%s.sql' % tag)
        t2 = tpl.replace(a, b)
        if tag == 'R2':   # the next statement then reads the limit again: take it away so only the same-statement read is left
            t2 = t2.replace("      select c.capacity_per_date, c.seat_mode into v_cap, v_mode from public.class_vouchers c where c.voucher_id = v_vid;", "")
        open(src, 'w').write(t2)
        r = subprocess.run(['python3', os.path.join(HERE, 'gen548.py')], env=dict(os.environ, SRC_SQL=src, OUT_SQL=out), capture_output=True, text=True)
        if r.returncode: print(tag, 'GEN FAILED', r.stderr[-300:]); continue
        r = subprocess.run(['python3', os.path.join(HERE, 'tests', 'race548.py'), out], capture_output=True, text=True)
        print('%-3s %-70s %s' % (tag, name.split(' ', 1)[1], 'CAUGHT' if r.returncode == 1 else 'NOT CAUGHT (rc %s)' % r.returncode), (r.stdout.strip().splitlines() or [''])[-1][:60])

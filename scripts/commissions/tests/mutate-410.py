"""Mutation checks for 410: each mutation below breaks one rule in a copy of
the migration, the copy's AFTER md5s are refilled (refill-410-md5s.py), and
the suite that guards the rule is run against the copy. A mutation is caught
when the suite FAILs (or refuses to run). Every run is a rolled-back
transaction on a disposable local database; the repository's migration is
not changed.

  python3 scripts/commissions/tests/mutate-410.py \
    [--db postgresql://postgres:postgres@127.0.0.1:54322/energia_events] [--prelude file.sql] [M1 M2 ...]
"""
import argparse, importlib.util, os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
_spec = importlib.util.spec_from_file_location('refill410', os.path.join(HERE, 'refill-410-md5s.py'))
refill = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(refill)

SUITES = {'clawbacks': 'scripts/commissions/tests/clawbacks-carried-forward.sql',
          'therapy': 'scripts/therapy/tests/status-refresh.sql'}
INCLUDE = '../../../supabase/410_clawbacks_carried_forward_and_therapy_status_refresh.sql'

MUTATIONS = [
    # ── affiliates ──
    ('M1', 'payout save: no cap at what the affiliate nets to', 'clawbacks',
     "   if delta>coalesce(v_payable,0) then\n", "   if false then\n"),
    ('M2', 'reconcile: what is taken back beyond the earlier take-backs keeps the paid row\'s date', 'clawbacks',
     "'adjusts_commission_id',v_a->>'id','invoice_paid_date',public.sg_today(),", "'adjusts_commission_id',v_a->>'id',"),
    ('M3', 'reconcile: the part never paid out is not split from what was paid out', 'clawbacks',
     "     v_left:=least(greatest(coalesce(public.commission_unpaid_amount(c.id),0),0),c.commission_amount);\n",
     "     v_left:=0;\n"),
    ('M4', 'overview: payable not shown oldest month first', 'clawbacks',
     "     r.payable-coalesce(sum(", "     1e9-coalesce(sum("),
    ('M5', 'directory: blocked still counts cancelled only', 'clawbacks',
     "and status in ('blocked','cancelled')),\n$q$;", "and status = 'cancelled'),\n$q$;"),
    ('M6', 'netting: a month under review counted when positive', 'clawbacks',
     "           else least(b.balance, 0) end), 0)", "           else b.balance end), 0)"),
    ('M7', 'portal: Unpaid may be negative', 'clawbacks',
     "'unpaid', greatest(v_unpaid, 0),", "'unpaid', v_unpaid,"),
    ('M16', 'reconcile: nothing netted against what the sale still earns (all taken back today)', 'clawbacks',
     "   v_take:=v_paid-least(v_paid,v_q);", "   v_take:=v_paid;"),
    ('M17', 'reconcile: earlier take-backs not kept on their dates', 'clawbacks',
     "   v_kept:=least(v_mem,v_paid);", "   v_kept:=0;"),
    ('M18', 'reconcile: the netting row linked to the paid row, not to the row earned again', 'clawbacks',
     "'adjusts_commission_id',m.id,'created_at',now(),\n      'reversed_at',null,'reversal_reason','Already paid out",
     "'adjusts_commission_id',(v_a->>'id')::uuid,'created_at',now(),\n      'reversed_at',null,'reversal_reason','Already paid out"),
    ('M19', 'reconcile: a refund undone lowers the earlier take-backs', 'clawbacks',
     "   v_kept:=least(v_mem,v_paid);", "   v_kept:=least(v_mem,v_paid-least(v_paid,v_q));"),
    ('M20', 'reconcile: earlier take-backs not read before they are reversed', 'clawbacks',
     "    and reversal_reason like 'Future payout adjustment: %';\n", "    and false;\n"),
    ('M21', 'reconcile: earlier take-backs never lowered when the payout was', 'clawbacks',
     "   v_drop:=v_mem-v_kept;", "   v_drop:=0;"),
    # ── therapy ──
    ('M8', 'consumed: stored status only', 'therapy',
     "       and (public.purchased_therapy_status_on(e.status, e.activation_date, e.expiry_date,\n"
     "                                               e.activation_deadline, public.sg_today()) in ('active','expired')\n",
     "       and (e.status in ('active','expired')\n"),
    ('M9', 'reschedule: a start date not checked (THERAPY-10)', 'therapy',
     "  if e.activation_date is not null then\n    raise exception 'This therapy is set to start",
     "  if false then\n    raise exception 'This therapy is set to start"),
    ('M10', 'rule: scheduled without a start date never expires', 'therapy',
     "    when p_status in ('pending_activation', 'scheduled') and p_activation is null",
     "    when p_status in ('pending_activation') and p_activation is null"),
    ('M11', 'rule: a start date of today is not yet started', 'therapy',
     "p_activation is not null and p_activation <= p_on then", "p_activation is not null and p_activation < p_on then"),
    ('M12', 'claim: stored status only', 'therapy',
     "    if v_now in ('active','expired') then\n      raise exception 'Unlimited therapy",
     "    if e.status in ('active','expired') then\n      raise exception 'Unlimited therapy"),
    ('M13', 'refresh: one unit it cannot move stops the run', 'therapy',
     "    exception when others then\n      raise warning", "    exception when division_by_zero then\n      raise warning"),
    ('M14', 'activate: stored status only', 'therapy',
     "  if v_now in ('active','expired','cancelled','refunded') then",
     "  if e.status in ('active','expired','cancelled','refunded') then"),
    ('M15', 'refund: stored status only', 'therapy',
     "                                        e.activation_deadline, public.sg_today()) in ('active','expired') then\n"
     "    -- Money",
     "                                        e.activation_deadline, public.sg_today()) in ('active','expired') and false then\n"
     "    -- Money"),
    ('M22', 'cancel: stored status only', 'therapy',
     "\n   and public.purchased_therapy_status_on(status,activation_date,expiry_date,activation_deadline,public.sg_today()) in ('pending_activation','scheduled');\n",
     ";\n"),
    ('M23', 'correct: stored status only', 'therapy',
     "     and public.purchased_therapy_status_on(status,activation_date,expiry_date,activation_deadline,public.sg_today()) in ('active','expired')) then\n",
     "     and status in ('active','expired')) then\n"),
    ('M24', 'refund: a unit never started by its deadline called "after activation"', 'therapy',
     "    if e.activation_date is null then\n      raise exception 'This therapy was not started",
     "    if false then\n      raise exception 'This therapy was not started"),
]


def fill(db, preludes, path):
    text = open(path).read()
    consts = dict(re.findall(r"\n  (c_\w+_after) constant text := '([0-9a-f]{32})';", text))
    fn_const = dict(re.findall(r"\n    \('([^']+\))', (c_\w+_after)\)", text))
    res = refill.run_once(db, preludes, path)
    m = re.search(r'installed with md5s other than the tested ones: (.*)', res.stderr)
    if not m:
        errors = [l for l in res.stderr.splitlines() if 'ERROR' in l]
        return ('the migration refused: ' + errors[0]) if errors else None
    for part in m.group(1).split('; '):
        fn, new = part.rsplit(' ', 1)
        text = text.replace(consts[fn_const[fn]], new.strip())
    open(path, 'w').write(text)
    res = refill.run_once(db, preludes, path)
    errors = [l for l in res.stderr.splitlines() if 'ERROR' in l]
    return ('still refused: ' + errors[0]) if errors else None


def run_suite(db, preludes, suite, mig, tmp):
    src = open(os.path.join(REPO, suite)).read()
    assert src.count(INCLUDE) >= 1
    path = os.path.join(tmp, os.path.basename(suite))
    open(path, 'w').write(src.replace(INCLUDE, mig))
    cmd = ['psql', '-X', '-v', 'ON_ERROR_STOP=1']
    if preludes:
        cmd += ['-v', 'prelude=' + os.path.abspath(preludes[0])]
    res = subprocess.run(cmd + [db, '-f', path], capture_output=True, text=True, cwd=os.path.dirname(os.path.join(REPO, suite)))
    lines = (res.stdout + res.stderr).splitlines()
    fails = [l.split('FAIL: ', 1)[1] for l in lines if 'FAIL: ' in l]
    errs = [l for l in lines if 'ERROR' in l and 'FAIL: ' not in l and 'is not the version' not in l
            and 'missing or not the version' not in l]
    return fails, errs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--db', default=os.environ.get('ENERGIA_LOCAL_DB_URL',
                                                   'postgresql://postgres:postgres@127.0.0.1:54322/energia_events'))
    ap.add_argument('--prelude', action='append', default=[])
    ap.add_argument('only', nargs='*')
    a = ap.parse_args()
    if not re.search(r'@(127\.0\.0\.1|localhost)(:\d+)?/', a.db):
        sys.exit('Refusing %s: local databases only.' % a.db)
    base = open(refill.MIGRATION).read()
    tmp = tempfile.mkdtemp(prefix='mutate410-')
    missed = 0
    try:
        for key, name, suite, old, new in MUTATIONS:
            if a.only and key not in a.only:
                continue
            label = '%-4s %s' % (key, name)
            n = base.count(old)
            if n != 1:
                print('%-90s SETUP: the text to mutate is found %d times' % (label, n)); missed += 1; continue
            mig = os.path.join(tmp, 'm410.sql')
            open(mig, 'w').write(base.replace(old, new))
            err = fill(a.db, a.prelude, mig)
            if err:
                print('%-90s CAUGHT by the migration itself: %s' % (label, err[:140])); continue
            fails, errs = run_suite(a.db, a.prelude, SUITES[suite], mig, tmp)
            if fails:
                print('%-90s CAUGHT: %s' % (label, fails[0][:150]))
            elif errs:
                print('%-90s ERRORED: %s' % (label, errs[0][:150]))
            else:
                print('%-90s MISSED' % label); missed += 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    sys.exit(1 if missed else 0)


if __name__ == '__main__':
    main()

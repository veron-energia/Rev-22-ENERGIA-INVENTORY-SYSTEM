"""Refill 410's AFTER md5s after its text or a BEFORE md5 changed (a rebase).

410 checks, after installing, that every function it writes has the md5 it
was tested with (its c_*_after constants), and refuses with
"410: installed with md5s other than the tested ones: <fn> <md5>; ..." when
one differs. This runs the migration inside a transaction that is always
rolled back, reads that refusal, and writes the md5s it names into the file,
replacing the old value everywhere it appears (the constant and the header's
AFTER list). Run it again and it reports that nothing is left to fill.

Disposable local databases only; nothing is written to the database. The
local database must hold production's text of every function 410 changes or
relies on: on a drifted one, pass --prelude with a file that installs them
(it runs inside the same transaction, before the migration). pg_cron is
stood in for when the database does not have it.

  python3 scripts/commissions/tests/refill-410-md5s.py \
    [--db postgresql://postgres:postgres@127.0.0.1:54322/energia_events] [--prelude file.sql ...]
"""
import argparse, os, re, subprocess, sys, tempfile

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
MIGRATION = os.path.join(REPO, 'supabase', '410_clawbacks_carried_forward_and_therapy_status_refresh.sql')
CRON_STUB = r"""
do $stub$
begin
  if to_regclass('cron.job') is null then
    create schema cron;
    create table cron.job(jobid bigserial primary key, schedule text not null, command text not null,
      nodename text not null default 'localhost', nodeport int not null default 5432,
      database text not null default current_database(), username text not null default current_user,
      active boolean not null default true, jobname text);
    create function cron.schedule(job_name text, schedule text, command text) returns bigint
    language plpgsql as $f$
    declare v bigint;
    begin
      update cron.job j set schedule = $2, command = $3, database = current_database(), username = current_user
       where j.jobname = $1 returning j.jobid into v;
      if v is null then
        insert into cron.job(schedule, command, jobname) values ($2, $3, $1) returning jobid into v; end if;
      return v;
    end $f$;
  end if;
end $stub$;
"""


def run_once(db, preludes, migration):
    with tempfile.NamedTemporaryFile('w', suffix='.sql', delete=False) as f:
        f.write('\\set ON_ERROR_STOP on\nbegin;\n')
        for p in preludes:
            f.write('\\i %s\n' % os.path.abspath(p))
        f.write(CRON_STUB)
        f.write('\\set ON_ERROR_STOP off\n\\i %s\nrollback;\n' % os.path.abspath(migration))
        runner = f.name
    try:
        return subprocess.run(['psql', '-X', '-q', db, '-f', runner], capture_output=True, text=True)
    finally:
        os.unlink(runner)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--db', default=os.environ.get('ENERGIA_LOCAL_DB_URL',
                                                   'postgresql://postgres:postgres@127.0.0.1:54322/energia_events'))
    ap.add_argument('--prelude', action='append', default=[])
    ap.add_argument('--migration', default=MIGRATION)
    a = ap.parse_args()
    if not re.search(r'@(127\.0\.0\.1|localhost)(:\d+)?/', a.db):
        sys.exit('Refusing %s: local databases only.' % a.db)

    text = open(a.migration).read()
    consts = dict(re.findall(r"\n  (c_\w+_after) constant text := '([0-9a-f]{32})';", text))
    fn_const = dict(re.findall(r"\n    \('([^']+\))', (c_\w+_after)\)", text))
    res = run_once(a.db, a.prelude, a.migration)
    errors = [l for l in res.stderr.splitlines() if 'ERROR' in l]
    m = re.search(r'installed with md5s other than the tested ones: (.*)', res.stderr)
    if not m:
        if errors:
            sys.exit('The migration refused before it installed anything:\n' + '\n'.join(errors))
        print('Nothing to fill: every AFTER md5 is the one installed.')
        return
    changed = 0
    for part in m.group(1).split('; '):
        fn, new = part.rsplit(' ', 1)
        new = new.strip()
        const = fn_const.get(fn)
        if not const or const not in consts:
            sys.exit('No AFTER constant found for %s' % fn)
        old = consts[const]
        n = text.count(old)
        if n < 1:
            sys.exit('%s: old md5 %s not found' % (fn, old))
        text = text.replace(old, new)
        changed += 1
        print('%-80s %s -> %s (%d places)' % (fn, old, new, n))
    open(a.migration, 'w').write(text)
    res = run_once(a.db, a.prelude, a.migration)
    if 'installed with md5s other than the tested ones' in res.stderr or any('ERROR' in l for l in res.stderr.splitlines()):
        sys.exit('Still refused after filling:\n' + res.stderr[-2000:])
    print('%d AFTER md5(s) filled; the migration now installs cleanly (rolled back).' % changed)


if __name__ == '__main__':
    main()

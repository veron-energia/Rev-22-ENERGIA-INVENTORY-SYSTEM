"""Apply the COMPLETE repository migration history to one disposable database.

Agent one's invoice fixture stops before 170 and its tests apply the invoice
migrations on top; the therapy, user, tiktok and therapy-service ranges were
never part of it. That leaves the one question nobody had answered: does the
whole history, in order, still build?

This answers it. It applies everything and RECORDS what fails instead of
skipping to a green result — a skipped migration is a finding, not a tidy-up.

Target is a database of its own. It never touches energia_invoice_test (agent
one's) or energia_auth_email_test (the therapy/users/tiktok suites).
"""
import os, pathlib, re, subprocess, sys, json

DB = 'energia_integration_test'
if os.environ.get('PGDATABASE') != DB or os.environ.get('PGHOST') != '/tmp':
    sys.exit(f'Refusing anything other than the isolated {DB} database')

def sql(s):
    return subprocess.run(['psql', '-X', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-q'],
                          input=s, text=True, capture_output=True)

r = sql('show data_directory;')
if r.returncode:
    sys.exit('Cannot reach the server: ' + r.stderr)
# Must be a project-owned cluster, never a system or production one.
if not pathlib.Path(r.stdout.strip()).resolve().is_relative_to(pathlib.Path.cwd()):
    sys.exit('Server is not a project-owned isolated cluster: ' + r.stdout.strip())

r = sql("""drop schema if exists public cascade; create schema public;
drop schema if exists auth cascade; create schema auth;
do $$ begin create role anon; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated; exception when duplicate_object then null; end $$;
do $$ begin create role service_role bypassrls; exception when duplicate_object then null; end $$;
drop schema if exists storage cascade; create schema storage;
create table storage.buckets(id text primary key,name text,public boolean);
create table storage.objects(id uuid,name text,bucket_id text,owner uuid);
create function storage.foldername(text) returns text[] language sql immutable as $$ select string_to_array($1,'/') $$;
create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,raw_user_meta_data jsonb default '{}'::jsonb);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
create function auth.role() returns text language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claim.role',true),''),'authenticated') $$;
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb $$;
""")
if r.returncode:
    sys.exit(r.stderr)

files = [p for p in pathlib.Path('supabase').glob('*.sql') if re.match(r'^[0-9]', p.name)]
files.sort(key=lambda p: (int(re.match(r'\d+', p.name)[0]), p.name))
files.insert(1, pathlib.Path('supabase/UPGRADE_to_current.sql'))

logs = pathlib.Path('.integration-test')
logs.mkdir(exist_ok=True)
failures = []
applied = 0
only = sys.argv[1:] if len(sys.argv) > 1 else None

for p in files:
    m = re.match(r'\d+', p.name)
    n = int(m[0]) if m else 0
    # 1-23 are folded into 00_complete_setup + UPGRADE_to_current, exactly as
    # agent one's fixture has it.
    if 1 <= n <= 23:
        continue
    if only and p.name not in only:
        continue
    r = sql(p.read_text())
    (logs / (p.stem + '.log')).write_text(r.stdout + r.stderr)
    if r.returncode:
        failures.append({'file': p.name, 'error': r.stderr.strip()[-1500:]})
        print(f'FAIL  {p.name}', flush=True)
    else:
        applied += 1
        print(f'ok    {p.name}', flush=True)

(logs / 'failures.json').write_text(json.dumps(failures, indent=2))
print(f'\napplied {applied}, failed {len(failures)}')
for f in failures:
    print(f"\n--- {f['file']} ---\n{f['error'][:600]}")
sys.exit(1 if failures else 0)

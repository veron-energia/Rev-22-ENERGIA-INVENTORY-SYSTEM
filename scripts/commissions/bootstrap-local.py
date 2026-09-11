"""Rebuild the complete schema in the exclusive local Commission fixture.

Stops on the first failed migration. Requires the exact database, socket,
port and project-owned data directory; never targets another test or live DB.
"""
import os, pathlib, re, subprocess, sys, json, argparse
parser = argparse.ArgumentParser()
parser.add_argument("--through", type=int, default=999999)
args = parser.parse_args()

DB = 'energia_commission_test'
if os.environ.get('PGDATABASE') != DB or os.environ.get('PGHOST') != '/tmp' or os.environ.get('PGPORT') != '55444':
    sys.exit(f'Refusing anything other than the isolated {DB} database')

def sql(s):
    return subprocess.run(['psql', '-X', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-q'],
                          input=s, text=True, capture_output=True)

r = sql('show data_directory;')
if r.returncode:
    sys.exit('Cannot reach the server: ' + r.stderr)
# Must be a project-owned cluster, never a system or production one.
if pathlib.Path(r.stdout.strip()).resolve() != pathlib.Path('.commission-test/data').resolve():
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

logs = pathlib.Path('.commission-test')
logs.mkdir(exist_ok=True)
failures = []
applied = 0

for p in files:
    m = re.match(r'\d+', p.name)
    n = int(m[0]) if m else 0
    # 1-23 are folded into 00_complete_setup + UPGRADE_to_current, exactly as
    # agent one's fixture has it.
    if n > args.through:
        continue
    if 1 <= n <= 23:
        continue
    r = sql(p.read_text())
    (logs / (p.stem + '.log')).write_text(r.stdout + r.stderr)
    if r.returncode:
        failures.append({'file': p.name, 'error': r.stderr.strip()[-1500:]})
        print(f'FAIL  {p.name}: {r.stderr[-2000:]}', flush=True)
        sys.exit(1)
    else:
        applied += 1
        print(f'ok    {p.name}', flush=True)

(logs / 'failures.json').write_text(json.dumps(failures, indent=2))
print(f'\napplied {applied}, failed {len(failures)}')
for f in failures:
    print(f"\n--- {f['file']} ---\n{f['error'][:600]}")
sys.exit(1 if failures else 0)

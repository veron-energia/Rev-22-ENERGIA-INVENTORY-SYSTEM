"""Apply repository history ONLY to a new, disposable invoice test database."""
import os, pathlib, re, subprocess, sys
if os.environ.get('PGDATABASE') != 'energia_invoice_test' or os.environ.get('PGHOST') != '/tmp' or os.environ.get('PGPORT') != '55441':
    sys.exit('Refusing anything other than the isolated local invoice test database')
def sql(s):
    return subprocess.run(['psql','-X','-A','-t','-v','ON_ERROR_STOP=1','-q'], input=s, text=True, capture_output=True)
r=sql('show data_directory;')
expected=pathlib.Path('.invoice-test/data').resolve()
if r.returncode or pathlib.Path(r.stdout.strip()).resolve()!=expected:
    sys.exit('Server is not the project-owned isolated test cluster')
r=sql("""drop schema if exists public cascade; create schema public; drop schema if exists auth cascade; create schema auth;
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
if r.returncode: sys.exit(r.stderr)
files=[p for p in pathlib.Path('supabase').glob('*.sql') if re.match(r'^[0-9]',p.name)]
files.sort(key=lambda p:(int(re.match(r'\d+',p.name)[0]),p.name))
files.insert(1,pathlib.Path('supabase/UPGRADE_to_current.sql'))
for p in files:
    n=int(re.match(r'\d+',p.name)[0]) if re.match(r'\d+',p.name) else 0
    if 1<=n<=23 or n>=170: continue
    if n == 130: print('KNOWN BASELINE FAILURE: 130 settlement duplicate anchor; excluded from invoice fixture',flush=True); continue
    r=sql(p.read_text())
    pathlib.Path('.invoice-test',p.stem+'.log').write_text(r.stdout+r.stderr)
    if r.returncode: sys.exit(p.name+'\n'+r.stderr[-4000:])
    print(p.name,flush=True)

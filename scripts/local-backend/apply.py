"""Apply the repository's migration history to the LOCAL Supabase stack.

Refuses anything that is not the local loopback database, so this can never be
pointed at a hosted project by accident.
"""
import pathlib, re, subprocess, sys

DB = "postgresql://postgres:postgres@127.0.0.1:54322/postgres"
if "127.0.0.1" not in DB and "localhost" not in DB:
    sys.exit("Refusing to apply migrations to anything but the local stack")

files = [p for p in pathlib.Path('supabase').glob('*.sql') if re.match(r'^[0-9]', p.name)]
files.sort(key=lambda p: (int(re.match(r'\d+', p.name)[0]), p.name))
files.insert(1, pathlib.Path('supabase/UPGRADE_to_current.sql'))

applied = 0
for p in files:
    m = re.match(r'\d+', p.name)
    n = int(m[0]) if m else 0
    # 1-23 are folded into 00_complete_setup + UPGRADE_to_current.
    if 1 <= n <= 23:
        continue
    r = subprocess.run(['psql', DB, '-X', '-q', '-v', 'ON_ERROR_STOP=1'],
                       input=p.read_text(), text=True, capture_output=True)
    if r.returncode:
        print(f'FAIL {p.name}: {r.stderr.strip()[-400:]}', flush=True)
        sys.exit(1)
    applied += 1
print(f'applied {applied} migrations to the local stack')

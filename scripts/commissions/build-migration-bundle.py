"""Print one atomic migration bundle. Never connects to a database."""
from pathlib import Path
files = ['280_affiliate_payout_allocations.sql', '281_affiliate_payout_api.sql', '282_affiliate_payout_reports.sql']
print('begin;\nset local lock_timeout = \'15s\';')
for name in files:
    sql = (Path(__file__).resolve().parents[2] / 'supabase' / name).read_text().strip()
    if not sql.startswith('begin;') or not sql.endswith('commit;'):
        raise SystemExit(f'Unexpected transaction structure in {name}; review before building.')
    print(f'\n-- {name}\n{sql[len("begin;"):-len("commit;")].strip()}')
print('\ncommit;')

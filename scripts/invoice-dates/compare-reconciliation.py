"""Compare hashes from reconciliation.sql; read-only local file processing."""
import json, pathlib, sys
before={r['table']:r for r in map(json.loads,pathlib.Path(sys.argv[1]).read_text().splitlines())}
after={r['table']:r for r in map(json.loads,pathlib.Path(sys.argv[2]).read_text().splitlines())}
allowed={'invoices_date_counts','recovery_events'}
changed=[key for key in sorted(before.keys()|after.keys()) if key not in allowed and before.get(key)!=after.get(key)]
if changed:
    print('STOP: operational data changed; investigate concurrent work or trigger drift:',', '.join(changed));sys.exit(1)
print('PASS: all operational hashes/counts unchanged')
for key in sorted(allowed): print(key, 'before=', before.get(key), 'after=', after.get(key))

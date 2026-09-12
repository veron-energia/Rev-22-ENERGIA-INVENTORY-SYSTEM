# A local backend for browser testing

Real browser-to-backend testing needs a Supabase stack that is **not** the
production project. This is how the one used to verify instalments was built,
reproducibly, without touching production.

Requires Docker Desktop running. No global install: `npx` fetches the CLI.

```bash
mkdir -p /tmp/energia-localstack && cd /tmp/energia-localstack
npx --yes supabase@latest init --force
npx --yes supabase@latest start            # first run pulls images; retries on ghcr are normal
npx --yes supabase@latest status -o json   # API_URL, ANON_KEY, DB_URL
```

Apply the repository's migration history to it (the same order the bootstrap
scripts use — `00_complete_setup`, `UPGRADE_to_current`, then every numbered
file, skipping 1–23 which are folded into those two):

```bash
python3 scripts/local-backend/apply.py
```

Create a synthetic owner and sign in as them:

```bash
SRK=$(cd /tmp/energia-localstack && npx --yes supabase@latest status -o json | python3 -c "import sys,json;print(json.load(sys.stdin)['SERVICE_ROLE_KEY'])")
curl -s -X POST http://127.0.0.1:54321/auth/v1/admin/users \
  -H "apikey: $SRK" -H "Authorization: Bearer $SRK" -H 'Content-Type: application/json' \
  -d '{"email":"owner@local.test","password":"LocalTest12345!","email_confirm":true}'
# then insert a matching public.profiles row with role 'owner'
```

Point the app at it with a `.env.local` (gitignored, and overriding `.env`):

```
VITE_SUPABASE_URL=http://127.0.0.1:54321
VITE_SUPABASE_ANON_KEY=<ANON_KEY from status>
```

**Check before testing.** Confirm the app is calling the loopback address and
not the production project — in the browser's network panel, or:

```bash
grep VITE_SUPABASE_URL .env.local     # must be http://127.0.0.1:54321
```

**Delete `.env.local` when finished**, or the dev server keeps pointing at a
stack that may no longer be running. `npx supabase stop` shuts the stack down.

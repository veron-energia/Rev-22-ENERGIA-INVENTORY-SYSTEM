# Deployment — Vercel

## Why direct links 404 (and why localhost was fine)

The app uses **client-side routing** (`BrowserRouter`). `/survey/<token>`,
`/invoices` and `/therapy` are **not real files** — there is only ever one:
`index.html`.

- **Dev:** Vite's server quietly serves `index.html` for any unknown path.
- **Vercel (before this fix):** looks for a real file at `/survey/abc123`,
  finds none, returns its own **404**. The app never loads, so React Router
  never gets to route.

Links *inside* the app worked because React handled them without asking the
server. Only **direct entry** — typing a URL, refreshing (F5), or **scanning a
QR code** — hits Vercel and broke.

> **This blocked the QR survey completely.** Customers scan straight into
> `/survey/<token>`, which is direct entry. The public New Customer Form could
> not work in production until now.

## The fix

`vercel.json` at the project root:

```json
{
  "$schema": "https://openapi.vercel.sh/vercel.json",
  "rewrites": [
    { "source": "/(.*)", "destination": "/index.html" }
  ]
}
```

**This does not break your assets.** Vercel checks the filesystem *before*
applying rewrites, so `/assets/index-abc123.js` still serves the real file and
only unmatched paths fall through to `index.html`. Verified: with the fallback,
JS assets still returned `200 text/javascript`, not HTML.

> **`vercel.json` must sit in the directory Vercel builds from.** If your Vercel
> project has a **Root Directory** set (Settings -> General), put `vercel.json`
> inside *that* folder, not the repo root — otherwise Vercel ignores it and the
> 404 persists. If the repo root *is* the app, you're fine.

The configs for other hosts have been removed now that we know it's Vercel.

## Deploy checklist

**1. Commit and push `vercel.json`.** Vercel redeploys automatically.

**2. Check Settings -> General:**
- Framework Preset: **Vite**
- Build Command: `npm run build` (your script is `tsc && vite build`)
- Output Directory: `dist`

These are normally auto-detected; only set them if they look wrong.

**3. Settings -> Environment Variables** — add for **Production** (and Preview
if you use it):
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

> **Then redeploy.** Vite inlines these at **build** time, not runtime. Saving a
> variable does nothing to an already-built site — you must trigger a new
> deployment (Deployments -> ... -> Redeploy). This catches almost everyone.

**4. Supabase -> Authentication -> URL Configuration:**
- **Site URL:** `https://yourdomain`
- **Redirect URLs:** add `https://yourdomain/**`

Without this, login can fail or bounce even once routing works.

## Verify after deploying

1. `https://yourdomain/invoices` typed directly -> loads (not 404).
2. Press **F5** on `/therapy` -> stays put, no 404.
3. `https://yourdomain/survey/<a real token>` -> the **New Customer Form** loads.
4. **Scan the QR** from the QR Links tab on a phone -> same. *(The real test.)*
5. DevTools -> Network -> hard reload -> `/assets/*.js` return **200** with type
   `text/javascript`. If they return `text/html`, tell me — it means the rewrite
   is being applied before the filesystem check.

## Tested

Reproduced against a filesystem-first static server (matching Vercel's routing
order), before and after the fallback:

| Path | Before | After |
|---|---|---|
| `/` | 200 | 200 |
| `/survey/abc123` | **404** | **200** |
| `/invoices` | **404** | **200** |
| `/therapy` | **404** | **200** |
| `/assets/index-*.js` | 200 | 200 (still the real file) |

The deep link returned the real app HTML (`<title>Energia — Inventory &
Sales</title>`), not an error page.

## If it still 404s

Most likely causes, in order:
1. **Root Directory mismatch** — `vercel.json` isn't in the folder Vercel builds
   from (see the warning above). This is the usual culprit.
2. **Not redeployed** since adding the file.
3. **App served from a subfolder** (`yourdomain/app`) — that also needs
   `base: '/app/'` in `vite.config.ts`. Tell me and I'll set it.

Check the deployment's **Build Logs** and confirm `vercel.json` was picked up.

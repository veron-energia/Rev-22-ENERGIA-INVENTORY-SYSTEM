# Verbatim copy — do not edit

`normalize.mjs` and `rules.json` here are **byte-identical copies** of
`src/lib/customer-phones/`. Edge Functions are deployed from `supabase/functions`
and cannot import from `src/`, so a copy is the only way to give the server the
same E.164 logic the browser and the database already use.

`tests/phone-copy.test.ts` fails if the copies ever drift from the originals.
Change `src/lib/customer-phones/` and re-copy; never edit these files directly.

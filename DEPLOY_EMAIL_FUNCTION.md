# WHY THE EMAIL BUTTON FAILED — AND HOW TO FIX IT

## The cause

Your DevTools panel answers it exactly:

| Request | Status |
|---|---|
| `send-invoice-email` — **preflight** | **404** |
| `send-invoice-email` — **fetch** | CORS error |

A **404 on the preflight** means there is nothing at that URL. The CORS error is
a *consequence*, not the cause: a 404 response carries no
`Access-Control-Allow-Origin` header, so the browser reports the follow-up
request as a CORS failure.

**The Edge Function has not been deployed yet.** That is step 2 of the previous
report, and it is the only thing missing.

## It is not localhost

The function sets `Access-Control-Allow-Origin: *`, so a call from
`localhost:3000` is accepted once the function exists. Running locally is fine
for testing this.

## Deploy it

From the project root, with the Supabase CLI logged in and linked:

```bash
supabase functions deploy send-invoice-email
supabase secrets set RESEND_API_KEY=re_xxxxxxxx
supabase secrets set INVOICE_FROM="Rev 22 Global Energia <info@rev22.com.sg>"
supabase secrets set INVOICE_REPLY_TO="info@rev22.com.sg"
```

Two things that catch people out:

1. **The sending domain must be verified with Resend.** Sending from an
   unverified domain is rejected — you will get "domain not verified" back, which
   the app now shows you verbatim.
2. **`INVOICE_FROM` must use that verified domain.** A Gmail or Hotmail address
   will not work as the sender.

Confirm it is live:

```bash
supabase functions list          # send-invoice-email should appear
```

Then send one invoice to your own address and check the PDF arrives attached.

## What I changed so this is never opaque again

**The error is now legible.** A 404 or the CORS failure it causes is recognised
as "the function is not deployed", and the app says so in plain words with the
command to run — instead of showing a raw CORS error that explains nothing.

**You are not blocked while you set it up.** If the function is unreachable, the
app uploads the PDF and opens your mail client with a **link** to it, and tells
you that is what happened and why:

> The email service is not set up yet, so your mail client has opened with a link
> to the PDF instead. To attach the PDF automatically, deploy the
> send-invoice-email function and set RESEND_API_KEY and INVOICE_FROM.

That is shown as a notice, not an error, and the send is logged in
`document_sends` as a link fallback — so your records stay honest about which
customers got a link rather than an attachment.

Once the function is deployed the fallback stops firing and the PDF is attached
properly, with no further change on your side.

## Files changed

- `src/lib/sendDoc.ts` — diagnose "not deployed", fall back to a link
- `src/pages/InvoicesPage.tsx` — show the fallback as a notice, not an error

## Manual steps

1. Deploy the function and set the two secrets, as above.
2. `npm install` → `npm run typecheck` → `npm run build` → deploy manually.

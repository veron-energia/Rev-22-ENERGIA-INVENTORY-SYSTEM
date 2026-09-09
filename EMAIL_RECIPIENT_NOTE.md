# WHY "TO:" WAS BLANK — AND WHAT I HAVE DONE

## The cause

This is a limitation of the **Web Share API**, not a bug in the code.

When the app hands the PDF to your Mac's share sheet, it can pass a **file**, a
**title** and **text** — and that is the whole list. The specification has no
recipient field. Mail therefore opens with the attachment in place and `To:`
empty, and no amount of code changes that on this route.

## What I have changed

Sending is now one paste instead of retyping:

- **The customer's address is copied to your clipboard** the moment the share
  sheet opens. Click into `To:` and paste.
- **It also appears as the first line of the message** (`To: judy@example.com`),
  so it is still visible if the clipboard is blocked — some browsers refuse
  clipboard access — and you can copy it from there.
- The confirmation now tells you which happened: *"The PDF is attached.
  judy@example.com has been copied — paste it into 'To:'."*

Delete the `To:` line from the body before sending if you would rather the
customer did not see it.

## The only way to have it filled automatically

**Deploy the Edge Function.** It sends server-side, so the recipient, subject,
body and attachment are all set without anyone touching the mail app:

```bash
supabase functions deploy send-invoice-email
supabase secrets set RESEND_API_KEY=re_xxxxxxxx
supabase secrets set INVOICE_FROM="Rev 22 Global Energia <info@rev22.com.sg>"
supabase secrets set INVOICE_REPLY_TO="info@rev22.com.sg"
```

That is the difference between the two routes, stated plainly:

| | PDF attached | "To:" filled | Needs deploying |
|---|---|---|---|
| Edge Function | yes | **yes** | yes, once |
| Share sheet (this) | yes | no — paste it | no |
| Link fallback | no, a link | yes | no |

There is no third option that attaches the file *and* fills the recipient from a
browser alone. Attaching a file to an addressed email is something only a server
can do.

## Files changed

- `src/lib/sendDoc.ts`

## Manual steps

`npm install` → `npm run typecheck` (0 errors) → `npm run build` (succeeds) →
deploy manually. Then send one to yourself: the address should already be on the
clipboard when Mail opens.

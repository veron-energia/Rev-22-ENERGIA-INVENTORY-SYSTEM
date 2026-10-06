# Affiliate login WhatsApp: setting up Pabbly (394)

Migration `supabase/394_affiliate_whatsapp_login_link.sql` queues one WhatsApp per
affiliate login that goes live (self sign-up, or staff Resolve) and per reactivation
of a suspended affiliate with a login. Every minute pg_cron posts what is waiting
to a Pabbly Connect webhook. Nothing is posted until the steps below are done and
sending is turned on. This file holds placeholders only: the real webhook address
and secret are never written into the repository (it is public).

## What Pabbly receives

One POST per message, JSON, flat:

| key               | example                                   |
|-------------------|-------------------------------------------|
| `secret`          | the shared secret (checked by the filter) |
| `idempotency_key` | `welcome:<login id>` or `reactivated:<affiliate id>:<time>` |
| `kind`            | `welcome` or `reactivated`                |
| `first_name`      | `Jane` (empty when none looks like a name) |
| `phone_e164`      | `+6591234567`                             |
| `wa_country_code` | `65`                                      |
| `wa_number`       | `91234567`                                |
| `message`         | the full text, line breaks included       |

A 2xx answer from Pabbly marks the message `sent`. Any other status code is
posted again 5 minutes later, at most 3 posts in all. A timeout or no answer is
never posted again (it may have gone out).

## 1. Build the workflow (Pabbly Connect, folder "Rev22 Energia")

1. Create a workflow, e.g. "Energia — Affiliate login link (WhatsApp)".
2. Trigger: **Webhook by Pabbly → Catch Webhook**. Copy the webhook URL it shows.
3. Do step 2 below (store the URL and a secret), then step 3 (one test post), so
   Pabbly captures a sample with the keys above.
4. Action: **Filter**. Condition: `secret` — *Text (Case sensitive) Exactly
   matches* — the secret from step 2. Anything else stops here. (A filter is
   free; no Code step is needed, and a Code step is a paid task.)
5. Action: **WbizTool send message**. Do not set up a new WbizTool connection
   and never type the WbizTool API key: copy the WbizTool step from an existing
   TikTok workflow (e.g. "Energia — Booking Changes") with Pabbly's *Copy step*,
   and *Paste step* it here, so it keeps its connection (the same WhatsApp sender as the TikTok lead messages).
   Map:
   - country code ← `wa_country_code`
   - phone / mobile number ← `wa_number`
   - message ← `message`
6. Save, and send the test post again (step 3) to your own number. Pabbly's
   WbizTool answer "Created" only means queued; check delivery in WbizTool's
   reports.

## 2. Store the webhook URL and a secret (Supabase SQL editor)

```sql
-- A secret: keep it only here and in the Pabbly filter.
select encode(extensions.gen_random_bytes(24), 'hex');

-- Sending stays off.
update public.affiliate_whatsapp_settings
   set webhook_url = '<PABBLY_CATCH_WEBHOOK_URL>',
       secret      = '<SECRET_FROM_THE_QUERY_ABOVE>',
       updated_at  = now()
 where id;
```

The URL must start with `https://`; the secret must be at least 16 characters.

## 3. One test post (to your own number)

```sql
select net.http_post(
  url := (select webhook_url from public.affiliate_whatsapp_settings where id),
  body := jsonb_build_object(
    'secret', (select secret from public.affiliate_whatsapp_settings where id),
    'idempotency_key', 'test:1', 'kind', 'welcome', 'first_name', 'Test',
    'phone_e164', '+65<YOUR_8_DIGITS>', 'wa_country_code', '65', 'wa_number', '<YOUR_8_DIGITS>',
    'message', public.affiliate_whatsapp_message('welcome', 'Test',
                 'https://rev-22-energia-inventory-system.vercel.app', 'ENTEST00')),
  timeout_milliseconds := 10000);
```

The referral link in the test text points at a code that does not exist; that is
fine for a test.

## 4. Turn sending on (and off)

```sql
update public.affiliate_whatsapp_settings set enabled = true,  updated_at = now() where id;
update public.affiliate_whatsapp_settings set enabled = false, updated_at = now() where id;
```

When it is turned on, messages queued in the last 48 hours are sent within a
minute; older ones are marked `expired` and never sent.

## 5. Watching it

```sql
select status, skip_reason, count(*) from public.affiliate_whatsapp_outbox group by 1, 2 order by 1, 2;

select id, kind, first_name, phone_e164, status, skip_reason, attempts,
       last_status_code, last_error, created_at, sent_at
  from public.affiliate_whatsapp_outbox
 order by id desc
 limit 20;
```

- `skipped`: never to be sent (`affiliate_suspended`, `no_phone`,
  `customer_deleted`, `no_longer_active`, ...). `earlier_message_pending` is a
  reactivation skipped because the welcome (or an earlier reactivation) for the
  same login was still waiting or being posted: that one has the same links.
- `failed` with `retry_after` empty: given up. Before sending one again by hand,
  check WbizTool's reports that it did not go out, then:
  `update public.affiliate_whatsapp_outbox set status = 'queued', attempts = 0, retry_after = null where id = <id>;`
  (only rows created in the last 48 hours are posted).

## 6. Changing the wording

The words live in one function, `public.affiliate_whatsapp_message(kind,
first_name, app_url, referral_code)`. Change them with a new migration that
replaces that function (guarded on 394's AFTER md5). Messages already queued keep
the words they were composed with.

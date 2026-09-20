// Supabase Edge Function — emails a customer their invoice with the PDF
// attached.
//
// A browser cannot attach a file to an email; only a server can. This function
// is that server. It takes the PDF the browser already generated (base64) and
// hands it to Resend, which does the delivery.
//
// Deploy:
//   supabase functions deploy send-invoice-email
//   supabase secrets set RESEND_API_KEY=re_xxxxxxxx
//   supabase secrets set INVOICE_FROM="Energia <invoices@yourdomain.com>"
//
// The FROM address must be on a domain verified with Resend, or delivery is
// rejected. Until both secrets are set the function returns a clear error and
// the app tells the staff member what is missing.
//
// WHO MAY CALL THIS
//
// This function used to make no authorization decision at all: it read the
// body and posted to Resend. Whether the gateway checks the JWT or not, that
// left "holds the publishable key" as the only barrier — and that key ships
// inside the browser bundle of a public web application. Recipient, subject,
// body and attachment are all caller-supplied, so anyone who viewed the site
// could send arbitrary mail with arbitrary attachments from the company's own
// verified domain.
//
// It now decides for itself, the way admin-invite-user does:
//
//   1. a bearer token must be present, and must resolve to a real user;
//   2. that user must have an active staff profile. The profiles read policy
//      requires a staff role (343), so an affiliate login reads nothing here
//      and is refused;
//   3. when the caller says which store the document belongs to, the database
//      is asked whether they may see that store, through the same
//      user_has_store_access() every invoice screen is gated on.
//
// Every one of those questions is answered by the database as the caller, so a
// role cannot be claimed in the body. Deploy WITHOUT --no-verify-jwt so the
// gateway checks the token as well; the function does not depend on it.

import { serve } from 'https://deno.land/std@0.208.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.108.2';
import { authorizeSend, bearerToken, type CallerClient } from './authorize.ts';

// Set INVOICE_ALLOWED_ORIGINS to a comma-separated list to restrict the
// browsers that may call this. Unset keeps the previous behaviour; the
// authorization above is the boundary, not this header.
const ALLOWED = (Deno.env.get('INVOICE_ALLOWED_ORIGINS') ?? '')
  .split(',').map((o) => o.trim()).filter(Boolean);

const corsFor = (origin: string | null) => ({
  'Access-Control-Allow-Origin':
    ALLOWED.length === 0 ? '*' : (origin && ALLOWED.includes(origin) ? origin : ALLOWED[0]),
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Vary': 'Origin',
});

/** Stored text goes into an HTML email; it must not be able to carry markup. */
const esc = (v: unknown) =>
  String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;')
                 .replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const jsonWith = (cors: Record<string, string>) => (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status, headers: { ...cors, 'Content-Type': 'application/json' },
  });

serve(async (req) => {
  const CORS = corsFor(req.headers.get('origin'));
  const json = jsonWith(CORS);
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Use POST.' }, 405);

  let payload: {
    to?: string; subject?: string; customerName?: string;
    docNo?: string; kindLabel?: string; storeId?: string | null;
    pdfBase64?: string; filename?: string; bodyText?: string;
  };
  try {
    payload = await req.json();
  } catch {
    return json({ error: 'The request body was not valid JSON.' }, 400);
  }

  // ---- who is asking ---------------------------------------------------
  // Before anything else, including the configuration check: an anonymous
  // caller should not learn whether this shop has email set up.
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const publicKey = Deno.env.get('SUPABASE_ANON_KEY');
  if (!supabaseUrl || !publicKey) {
    return json({ error: 'Email is not configured yet: this function cannot reach the database to check who is asking.' }, 503);
  }

  const token = bearerToken(req.headers.get('Authorization'));
  if (!token) {
    return json({ error: 'Please sign in again and retry.' }, 401);
  }

  // The caller's own token, so auth.uid() in the database is them and a role
  // cannot be claimed in the body.
  const caller = createClient(supabaseUrl, publicKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  }) as unknown as CallerClient;

  const decision = await authorizeSend(caller, payload.storeId);
  if (!decision.ok) return json({ error: decision.error }, decision.status);

  const apiKey = Deno.env.get('RESEND_API_KEY');
  const from = Deno.env.get('INVOICE_FROM');
  // Replies to an invoice should reach the same mailbox as everything else.
  // Falls back to the From address, which is what happens today when no
  // Reply-To is set, so an unconfigured project behaves exactly as before.
  const replyTo = Deno.env.get('INVOICE_REPLY_TO') || from;
  if (!apiKey || !from) {
    return json({
      error: 'Email is not configured yet. Set RESEND_API_KEY and INVOICE_FROM '
           + 'on this function, then try again.',
    }, 503);
  }

  const { to, pdfBase64 } = payload;
  if (!to || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(to)) {
    return json({ error: 'A valid recipient email address is required.' }, 400);
  }
  if (!pdfBase64) return json({ error: 'The invoice PDF was missing from the request.' }, 400);

  const docNo = payload.docNo ?? 'Invoice';
  const kind = payload.kindLabel ?? 'Invoice';
  const name = payload.customerName?.trim();
  const greeting = name ? `Hi ${name},` : 'Hi,';

  const text = payload.bodyText ?? [
    greeting, '',
    `Please find your ${kind.toLowerCase()} ${docNo} attached.`, '',
    'Thank you for shopping with Energia.',
  ].join('\n');

  // Escaped: docNo, kindLabel and customerName are stored values that reach
  // this from a form, and they are being written into HTML.
  const html = `<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#111">
      <p>${esc(greeting)}</p>
      <p>Please find your ${esc(kind.toLowerCase())} <strong>${esc(docNo)}</strong> attached.</p>
      <p>Thank you for shopping with Energia.</p>
    </div>`;

  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from,
        reply_to: replyTo,
        to: [to],
        subject: payload.subject ?? `${kind} ${docNo} — Energia`,
        text, html,
        attachments: [{
          filename: payload.filename ?? `${docNo}.pdf`,
          content: pdfBase64,          // base64, as Resend expects
        }],
      }),
    });

    const body = await res.json().catch(() => ({}));
    if (!res.ok) {
      // Pass the provider's own wording through: "domain not verified" is far
      // more useful to the shop than a generic failure.
      return json({ error: body?.message ?? `Email provider returned ${res.status}.` }, 502);
    }
    return json({ ok: true, id: body?.id ?? null });
  } catch (e) {
    return json({ error: `Could not reach the email provider: ${String(e)}` }, 502);
  }
});

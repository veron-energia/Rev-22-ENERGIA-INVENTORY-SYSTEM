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

import { serve } from 'https://deno.land/std@0.208.0/http/server.ts';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status, headers: { ...CORS, 'Content-Type': 'application/json' },
  });

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Use POST.' }, 405);

  const apiKey = Deno.env.get('RESEND_API_KEY');
  const from = Deno.env.get('INVOICE_FROM');
  if (!apiKey || !from) {
    return json({
      error: 'Email is not configured yet. Set RESEND_API_KEY and INVOICE_FROM '
           + 'on this function, then try again.',
    }, 503);
  }

  let payload: {
    to?: string; subject?: string; customerName?: string;
    docNo?: string; kindLabel?: string;
    pdfBase64?: string; filename?: string; bodyText?: string;
  };
  try {
    payload = await req.json();
  } catch {
    return json({ error: 'The request body was not valid JSON.' }, 400);
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

  const html = `<div style="font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#111">
      <p>${greeting}</p>
      <p>Please find your ${kind.toLowerCase()} <strong>${docNo}</strong> attached.</p>
      <p>Thank you for shopping with Energia.</p>
    </div>`;

  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from,
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

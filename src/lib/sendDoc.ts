/**
 * Sending an invoice or receipt to a customer by WhatsApp or email.
 *
 * Both open the staff member's own WhatsApp and mail client with the message
 * already written, rather than sending from a server. That means no email
 * provider, no API keys and no per-message cost, and the staff member sees
 * exactly what goes out before it goes. The trade-off is that a PDF cannot be
 * attached automatically — see composeDocumentMessage below.
 */

/** Placeholder values used for customers with no real contact details. */
const PLACEHOLDER = /^(LEGACY[- ]?NO[- ]?PHONE|NO[- ]?PHONE|N\/?A|-|—)/i;

/**
 * Turn a stored phone number into the digits-only international form wa.me
 * needs. Returns null when the number is missing, a placeholder, or too short
 * to be real, so the caller can disable the button rather than open a broken
 * chat.
 */
export function whatsappNumber(raw: string | null | undefined, defaultCountry = '65'): string | null {
  const s = String(raw ?? '').trim();
  if (!s || PLACEHOLDER.test(s)) return null;

  const hadPlus = s.startsWith('+');
  const digits = s.replace(/\D/g, '');
  if (digits.length < 7) return null;

  // An 8-digit local Singapore number gets the country code added; anything
  // already carrying one is left alone.
  if (!hadPlus && digits.length === 8) return defaultCountry + digits;
  return digits;
}

/** A usable email address, or null. */
export function emailAddress(raw: string | null | undefined): string | null {
  const s = String(raw ?? '').trim();
  if (!s || PLACEHOLDER.test(s)) return null;
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s) ? s : null;
}

export interface SendableLine {
  name: string;
  qty?: number | string;
  total?: number | string | null;
}

export interface SendableDoc {
  /** "Invoice", "Sale", "Rental" */
  kindLabel: string;
  docNo: string;
  date?: string;
  customerName?: string | null;
  storeName?: string | null;
  lines: SendableLine[];
  totals: [string, string][];
  /** e.g. ["CIMB UEN: 201104431Z", "CIMB corporate account: …"] */
  payDetails?: string[];
  /** Closing note, e.g. opening hours or a thank-you. */
  footerNote?: string;
}

const money = (v: any) =>
  typeof v === 'number' ? `S$${v.toFixed(2)}` : String(v ?? '');

/**
 * The message body, shared by both channels so a customer receives the same
 * wording whichever is used. Kept compact: mail clients and WhatsApp both
 * truncate very long URLs, and a wall of text is not what a customer wants.
 */
export function composeDocumentMessage(d: SendableDoc): string {
  const parts: string[] = [];
  parts.push(`${d.kindLabel} ${d.docNo}`);
  if (d.customerName) parts.push(`For: ${d.customerName}`);
  if (d.storeName) parts.push(d.storeName);
  if (d.date) parts.push(`Date: ${d.date}`);
  parts.push('');

  if (d.lines.length > 0) {
    parts.push('Items');
    // Cap the list so the link stays within the length mail clients accept.
    const MAX = 12;
    for (const l of d.lines.slice(0, MAX)) {
      const qty = l.qty != null && l.qty !== '' ? ` x${l.qty}` : '';
      parts.push(`- ${l.name}${qty}${l.total != null ? ` — ${money(l.total)}` : ''}`);
    }
    if (d.lines.length > MAX) parts.push(`- …and ${d.lines.length - MAX} more item(s)`);
    parts.push('');
  }

  for (const [label, value] of d.totals) parts.push(`${label}: ${value}`);

  if (d.payDetails?.length) {
    parts.push('');
    parts.push('How to pay');
    for (const p of d.payDetails) parts.push(p);
  }

  parts.push('');
  parts.push(d.footerNote ?? 'Thank you for shopping with Energia.');
  return parts.join('\n');
}

/** Open WhatsApp with the message ready to send. */
export function sendViaWhatsApp(phone: string | null | undefined, message: string): { ok: boolean; reason?: string } {
  const num = whatsappNumber(phone);
  if (!num) return { ok: false, reason: 'This customer has no usable mobile number.' };
  // wa.me works on desktop (WhatsApp Web) and on mobile (the app).
  window.open(`https://wa.me/${num}?text=${encodeURIComponent(message)}`, '_blank', 'noopener');
  return { ok: true };
}

/** Open the mail client with the message ready to send. */
export function sendViaEmail(
  email: string | null | undefined, subject: string, message: string,
): { ok: boolean; reason?: string } {
  const addr = emailAddress(email);
  if (!addr) return { ok: false, reason: 'This customer has no valid email address.' };
  const href = `mailto:${encodeURIComponent(addr)}`
    + `?subject=${encodeURIComponent(subject)}`
    + `&body=${encodeURIComponent(message)}`;
  // A very long mailto is silently dropped by some clients; warn rather than
  // opening something that will not work.
  // ~2000 characters is the practical ceiling across mail clients. The item
  // list is capped above, so a real invoice lands well inside this; the guard
  // is for pathological cases such as very long product names.
  if (href.length > 2000) {
    return { ok: false, reason: 'This document is too long to send by email link. Please print it to PDF and attach it instead.' };
  }
  window.location.href = href;
  return { ok: true };
}

// ---------------------------------------------------------------------
// Sending
//
// WhatsApp receives a LINK to the customer copy: WhatsApp cannot be handed a
// file from a browser, and a link opens instantly on a phone.
//
// Email receives the PDF as a REAL ATTACHMENT, sent by the send-invoice-email
// Edge Function. Only a server can attach a file to an email; the browser
// generates the PDF and the function delivers it.
// ---------------------------------------------------------------------
import { supabase } from './supabase';
import { documentPdfBlob, downloadDocumentPdf, PdfDoc } from './invoicePdf';
import { documentImageBlob } from './invoiceImage';

export type DocFormat = 'pdf' | 'image';

const BUCKET = 'invoice-pdfs';
/** Signed links last a year: a customer may open theirs months later. */
const LINK_SECONDS = 60 * 60 * 24 * 365;

const safeName = (docNo: string) => docNo.replace(/[^A-Za-z0-9._-]/g, '-');

/** base64 without the data: prefix, which is what the email API expects. */
async function blobToBase64(blob: Blob): Promise<string> {
  const buf = await blob.arrayBuffer();
  let binary = '';
  const bytes = new Uint8Array(buf);
  const CHUNK = 0x8000;
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return btoa(binary);
}

/** Upload the customer copy and return a link the customer can open. */
export async function uploadDocumentPdf(
  storeId: string | null | undefined, docKind: string, docNo: string, pdf: PdfDoc,
): Promise<{ url: string; path: string }> {
  const blob = documentPdfBlob(pdf);
  // A stable path means re-sending replaces the file rather than accumulating
  // near-identical copies.
  const path = `${storeId ?? 'no-store'}/${docKind}/${safeName(docNo)}.pdf`;
  const { error: upErr } = await supabase.storage.from(BUCKET)
    .upload(path, blob, { contentType: 'application/pdf', upsert: true });
  if (upErr) throw new Error(`Could not upload the PDF: ${upErr.message}`);

  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(path, LINK_SECONDS);
  if (error || !data?.signedUrl) throw new Error('The PDF was uploaded but no link could be created.');
  return { url: data.signedUrl, path };
}

export interface SendArgs {
  pdf: PdfDoc;
  kindLabel: string;
  docNo: string;
  docId?: string | null;
  docKind: 'invoice' | 'special_sale' | 'rental';
  storeId?: string | null;
  customerId?: string | null;
  customerName?: string | null;
  phone?: string | null;
  email?: string | null;
}

const logSend = (a: SendArgs, channel: string, to: string, path: string | null,
                 status: 'sent' | 'failed', err?: string) => {
  // Best effort: a failed audit write must not look like a failed send.
  void supabase.rpc('record_document_send', {
    p_doc_kind: a.docKind, p_doc_no: a.docNo, p_channel: channel,
    p_doc_id: a.docId ?? null, p_customer_id: a.customerId ?? null,
    p_sent_to: to, p_pdf_path: path, p_status: status, p_error: err ?? null,
  });
};

/** WhatsApp: upload the PDF, then open the chat with a link to it. */
export async function sendViaWhatsAppLink(a: SendArgs): Promise<{ ok: boolean; reason?: string }> {
  const num = whatsappNumber(a.phone);
  if (!num) return { ok: false, reason: 'This customer has no usable mobile number.' };

  let url: string, path: string;
  try {
    ({ url, path } = await uploadDocumentPdf(a.storeId, a.docKind, a.docNo, a.pdf));
  } catch (e: any) {
    logSend(a, 'whatsapp', num, null, 'failed', e?.message);
    return { ok: false, reason: e?.message ?? 'Could not prepare the PDF.' };
  }

  const message = [
    a.customerName ? `Hi ${a.customerName},` : 'Hi,', '',
    `Here is your ${a.kindLabel.toLowerCase()} ${a.docNo} from Energia:`,
    url, '',
    'Thank you for shopping with Energia.',
  ].join('\n');

  window.open(`https://wa.me/${num}?text=${encodeURIComponent(message)}`, '_blank', 'noopener');
  logSend(a, 'whatsapp', num, path, 'sent');
  return { ok: true };
}

/** Email: send the PDF as a real attachment via the Edge Function. */
export async function sendViaEmailAttachment(
  a: SendArgs,
): Promise<{ ok: boolean; reason?: string; fellBackToLink?: boolean }> {
  const addr = emailAddress(a.email);
  if (!addr) return { ok: false, reason: 'This customer has no valid email address.' };

  let base64: string;
  try {
    base64 = await blobToBase64(documentPdfBlob(a.pdf));
  } catch (e: any) {
    return { ok: false, reason: e?.message ?? 'Could not prepare the PDF.' };
  }

  let data: any = null, error: any = null;
  try {
    ({ data, error } = await supabase.functions.invoke('send-invoice-email', {
      body: {
        to: addr,
        subject: `${a.kindLabel} ${a.docNo} — Energia`,
        customerName: a.customerName ?? null,
        docNo: a.docNo, kindLabel: a.kindLabel,
        filename: `${safeName(a.docNo)}.pdf`,
        pdfBase64: base64,
      },
    }));
  } catch (e: any) {
    error = e;
  }

  const status = error?.context?.status ?? error?.status;
  const raw = String(error?.message ?? '');

  // A 404 on the function URL, or the CORS/network failure that a 404 causes,
  // both mean the same thing: the function is not deployed. The browser
  // reports this as an opaque CORS error, which tells the shop nothing.
  const notDeployed =
    status === 404 ||
    /failed to (fetch|send)|networkerror|load failed|cors/i.test(raw);

  if (notDeployed) {
    // Rather than leaving the customer without their invoice, fall back to the
    // link — the same PDF, delivered a different way — and say so plainly.
    try {
      const { url, path } = await uploadDocumentPdf(a.storeId, a.docKind, a.docNo, a.pdf);
      const body = [
        a.customerName ? `Hi ${a.customerName},` : 'Hi,', '',
        `Here is your ${a.kindLabel.toLowerCase()} ${a.docNo} from Energia:`,
        url, '',
        'Thank you for shopping with Energia.',
      ].join('\n');
      window.location.href = `mailto:${encodeURIComponent(addr)}`
        + `?subject=${encodeURIComponent(`${a.kindLabel} ${a.docNo} — Energia`)}`
        + `&body=${encodeURIComponent(body)}`;
      logSend(a, 'email', addr, path, 'sent', 'link fallback — email function not deployed');
      return {
        ok: true, fellBackToLink: true,
        reason: 'The email service is not set up yet, so your mail client has opened with a '
              + 'link to the PDF instead. To attach the PDF automatically, deploy the '
              + 'send-invoice-email function and set RESEND_API_KEY and INVOICE_FROM.',
      };
    } catch (e: any) {
      logSend(a, 'email', addr, null, 'failed', 'function not deployed; link fallback failed');
      return {
        ok: false,
        reason: 'The email service is not set up yet. Deploy the send-invoice-email function '
              + '(supabase functions deploy send-invoice-email) and set RESEND_API_KEY and '
              + 'INVOICE_FROM, then try again.',
      };
    }
  }

  // The function replied, so show whatever it or the provider actually said —
  // "domain not verified" is far more useful than a generic failure.
  const reason = data?.error ?? (error ? (error?.context?.error ?? error.message) : null);
  if (error || reason) {
    logSend(a, 'email', addr, null, 'failed', String(reason ?? 'unknown'));
    return { ok: false, reason: String(reason ?? 'The email could not be sent.') };
  }

  logSend(a, 'email', addr, null, 'sent');
  return { ok: true };
}

/** Save the customer copy locally. */
export async function saveDocumentFile(pdf: PdfDoc, format: DocFormat, docNo: string): Promise<void> {
  if (format === 'image') {
    const blob = await documentImageBlob(pdf);
    const url = URL.createObjectURL(blob);
    const el = document.createElement('a');
    el.href = url; el.download = `${safeName(docNo)}.png`;
    document.body.appendChild(el); el.click(); el.remove();
    setTimeout(() => URL.revokeObjectURL(url), 30000);
    return;
  }
  downloadDocumentPdf(pdf, `${safeName(docNo)}.pdf`);
}

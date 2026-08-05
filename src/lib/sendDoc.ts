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
// Sending the actual PDF
// ---------------------------------------------------------------------
import { supabase } from './supabase';
import { documentPdfBlob, downloadDocumentPdf, PdfDoc } from './invoicePdf';

const BUCKET = 'invoice-pdfs';
/** Signed links last a year — a customer may open theirs months later. */
const LINK_SECONDS = 60 * 60 * 24 * 365;

/**
 * Renders the customer copy, uploads it and returns a link the customer can
 * open. The file is a real A5 PDF of a few tens of kilobytes, so it opens
 * instantly on a phone.
 */
export async function uploadDocumentPdf(
  storeId: string | null | undefined, docKind: string, docNo: string, pdf: PdfDoc,
): Promise<{ url: string; path: string }> {
  const blob = documentPdfBlob(pdf);
  const safeNo = docNo.replace(/[^A-Za-z0-9._-]/g, '-');
  // Upserting on a stable path means re-sending replaces the file rather than
  // littering storage with near-identical copies.
  const path = `${storeId ?? 'no-store'}/${docKind}/${safeNo}.pdf`;

  const { error: upErr } = await supabase.storage.from(BUCKET)
    .upload(path, blob, { contentType: 'application/pdf', upsert: true });
  if (upErr) throw new Error(`Could not upload the PDF: ${upErr.message}`);

  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(path, LINK_SECONDS);
  if (error || !data?.signedUrl) throw new Error('The PDF was uploaded but no link could be created.');
  return { url: data.signedUrl, path };
}

/** A short covering note; the PDF itself carries the detail. */
export function pdfCoveringMessage(kindLabel: string, docNo: string, customerName: string | null | undefined, url: string): string {
  return [
    customerName ? `Hi ${customerName},` : 'Hi,',
    '',
    `Here is your ${kindLabel.toLowerCase()} ${docNo} from Energia:`,
    url,
    '',
    'Thank you for shopping with Energia.',
  ].join('\n');
}

export interface SendPdfArgs {
  channel: 'whatsapp' | 'email';
  phone?: string | null;
  email?: string | null;
  storeId?: string | null;
  docKind: 'invoice' | 'special_sale' | 'rental';
  kindLabel: string;
  docNo: string;
  docId?: string | null;
  customerId?: string | null;
  customerName?: string | null;
  pdf: PdfDoc;
}

/**
 * Build the PDF, upload it, then hand off to WhatsApp or the mail client with
 * the link in the message. Returns a reason instead of throwing so the caller
 * can show it inline.
 */
export async function sendDocumentPdf(a: SendPdfArgs): Promise<{ ok: boolean; reason?: string }> {
  const target = a.channel === 'whatsapp' ? whatsappNumber(a.phone) : emailAddress(a.email);
  if (!target) {
    return { ok: false, reason: a.channel === 'whatsapp'
      ? 'This customer has no usable mobile number.'
      : 'This customer has no valid email address.' };
  }

  let url: string, path: string;
  try {
    ({ url, path } = await uploadDocumentPdf(a.storeId, a.docKind, a.docNo, a.pdf));
  } catch (e: any) {
    return { ok: false, reason: e?.message ?? 'Could not prepare the PDF.' };
  }

  const message = pdfCoveringMessage(a.kindLabel, a.docNo, a.customerName, url);

  if (a.channel === 'whatsapp') {
    window.open(`https://wa.me/${target}?text=${encodeURIComponent(message)}`, '_blank', 'noopener');
  } else {
    window.location.href = `mailto:${encodeURIComponent(target)}`
      + `?subject=${encodeURIComponent(`${a.kindLabel} ${a.docNo} — Energia`)}`
      + `&body=${encodeURIComponent(message)}`;
  }

  // Best effort: a failed audit write must not look like a failed send.
  void supabase.rpc('record_document_send', {
    p_doc_kind: a.docKind, p_doc_no: a.docNo, p_channel: a.channel,
    p_doc_id: a.docId ?? null, p_customer_id: a.customerId ?? null,
    p_sent_to: target, p_pdf_path: path,
  });

  return { ok: true };
}

/** Save the customer copy locally, for attaching by hand if preferred. */
export function saveDocumentPdf(pdf: PdfDoc, docNo: string): void {
  downloadDocumentPdf(pdf, `${docNo.replace(/[^A-Za-z0-9._-]/g, '-')}.pdf`);
}

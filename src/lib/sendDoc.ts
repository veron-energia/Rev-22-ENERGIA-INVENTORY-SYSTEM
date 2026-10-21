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
// Email goes from this device's own mail app (the Owner, 9 Oct 2026, Q6 =
// option 2: no email-sending service). On a phone the share sheet hands the
// real PDF to the mail app; on a computer the mail app opens with a link to
// the PDF, because a browser cannot attach a file to an email on its own.
// The page says which happened and never says a PDF was attached or sent when
// it was not: a closed share sheet is "Not sent", logged as failed. The
// send-invoice-email Edge Function this used to try first was never built,
// so that call is gone (B16, AFTER-M3).
// ---------------------------------------------------------------------
import { supabase } from './supabase';
import { documentPdfBlob, downloadDocumentPdf, PdfDoc } from './invoicePdf';
import { documentImageBlob } from './invoiceImage';

export type DocFormat = 'pdf' | 'image';

const BUCKET = 'invoice-pdfs';
/** Signed links last a year: a customer may open theirs months later. */
const LINK_SECONDS = 60 * 60 * 24 * 365;

const safeName = (docNo: string) => docNo.replace(/[^A-Za-z0-9._-]/g, '-');

/**
 * A name no earlier send used. Each send is filed under its own name and never
 * replaces a file, so the link a customer already holds keeps showing the copy
 * they were sent: nobody can point an old link at a different PDF (407).
 */
export function documentPdfPath(storeId: string | null | undefined, docKind: string, docNo: string): string {
  const unique = typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
    ? crypto.randomUUID()
    : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}`;
  // The first folder is the store: the folder's rules let only that store's
  // staff (and Managers and up) read or upload the file.
  return `${storeId ?? 'no-store'}/${docKind}/${safeName(docNo)}-${unique}.pdf`;
}

/** Upload the customer copy and return a link the customer can open. */
export async function uploadDocumentPdf(
  storeId: string | null | undefined, docKind: string, docNo: string, pdf: PdfDoc,
): Promise<{ url: string; path: string }> {
  const blob = documentPdfBlob(pdf);
  const path = documentPdfPath(storeId, docKind, docNo);
  const { error: upErr } = await supabase.storage.from(BUCKET)
    .upload(path, blob, { contentType: 'application/pdf', upsert: false });
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
  // Best effort: a failed audit write must not look like a failed send, so it
  // is neither awaited nor allowed to throw. The client only sends a request
  // once then() is called on it — "void supabase.rpc(...)" alone never did,
  // and the send log stayed empty (389).
  void supabase.rpc('record_document_send', {
    p_doc_kind: a.docKind, p_doc_no: a.docNo, p_channel: channel,
    p_doc_id: a.docId ?? null, p_customer_id: a.customerId ?? null,
    p_sent_to: to, p_pdf_path: path, p_status: status, p_error: err ?? null,
  }).then(
    ({ error }) => { if (error) console.warn('The send was not logged:', error.message); },
    (e) => console.warn('The send was not logged:', e),
  );
};

/** Said when the browser would not open the WhatsApp window (a pop-up blocker). */
export const WHATSAPP_BLOCKED = 'Your browser blocked the WhatsApp window. Allow pop-ups for this site, then press WhatsApp again.';

/**
 * A blank window for a WhatsApp send, opened in the click itself, before
 * anything is awaited (B16, AFTER-11). A window opened after the upload is
 * past the click, and a phone's pop-up blocker (iPhone Safari above all)
 * stops it. Null when the browser refused it.
 */
export function openSendWindow(): Window | null {
  let w: Window | null = null;
  try { w = window.open('', '_blank'); } catch { w = null; }
  if (w) {
    try { w.document.title = 'WhatsApp'; if (w.document.body) w.document.body.textContent = 'Preparing the invoice link…'; }
    catch { /* left blank */ }
  }
  return w;
}

export interface SendOptions {
  /** The window openSendWindow opened in the click; null when it was refused.
   *  Left out (the Special page today), a window is opened once the link is
   *  ready, and a refusal is still reported, never logged as sent. */
  win?: Window | null;
}

/**
 * WhatsApp: upload the PDF, then open the chat with a link to it. 'sent' is
 * logged only once a window was really obtained and pointed at the chat
 * (AFTER-11); a blocked or closed window is 'failed', with the reason.
 */
export async function sendViaWhatsAppLink(a: SendArgs, opts: SendOptions = {}): Promise<{ ok: boolean; reason?: string }> {
  const given = 'win' in opts;
  const closeGiven = () => { try { if (opts.win && !opts.win.closed) opts.win.close(); } catch { /* gone already */ } };
  const num = whatsappNumber(a.phone);
  if (!num) { closeGiven(); return { ok: false, reason: 'This customer has no usable mobile number.' }; }
  if (given && !opts.win) {
    logSend(a, 'whatsapp', num, null, 'failed', 'pop-up blocked');
    return { ok: false, reason: WHATSAPP_BLOCKED };
  }

  let url: string, path: string;
  try {
    ({ url, path } = await uploadDocumentPdf(a.storeId, a.docKind, a.docNo, a.pdf));
  } catch (e: any) {
    closeGiven();
    logSend(a, 'whatsapp', num, null, 'failed', e?.message);
    return { ok: false, reason: e?.message ?? 'Could not prepare the PDF.' };
  }

  const message = [
    a.customerName ? `Hi ${a.customerName},` : 'Hi,', '',
    `Here is your ${a.kindLabel.toLowerCase()} ${a.docNo} from Energia:`,
    url, '',
    'Thank you for shopping with Energia.',
  ].join('\n');
  const chat = `https://wa.me/${num}?text=${encodeURIComponent(message)}`;

  // 'noopener' made window.open return null whether or not a window opened,
  // so a blocked one could not be told apart. The new window's link back to
  // this page is cut by hand instead.
  let w: Window | null = given ? opts.win! : null;
  if (w && w.closed) {
    logSend(a, 'whatsapp', num, path, 'failed', 'window closed');
    return { ok: false, reason: 'The WhatsApp window was closed before the link was ready. Press WhatsApp again.' };
  }
  try {
    if (w) { w.opener = null; w.location.href = chat; }
    else { w = window.open(chat, '_blank'); if (w) w.opener = null; }
  } catch { w = null; }
  if (!w) {
    logSend(a, 'whatsapp', num, path, 'failed', 'pop-up blocked');
    return { ok: false, reason: WHATSAPP_BLOCKED };
  }
  logSend(a, 'whatsapp', num, path, 'sent');
  return { ok: true };
}

/** Can this device attach a real file to a share? (Phones can; desktops cannot.) */
export function canShareFiles(): boolean {
  try {
    const nav: any = navigator;
    if (!nav?.canShare || !nav?.share) return false;
    return !!nav.canShare({ files: [new File(['x'], 'p.pdf', { type: 'application/pdf' })] });
  } catch { return false; }
}

/** 'shared': the PDF went to an app on this device (the share sheet); 'link':
 *  the mail app was asked to open with a link to the PDF. */
export type EmailOutcome = 'shared' | 'link';

export interface EmailResult {
  ok: boolean;
  /** What to tell the person, in a sentence. */
  reason?: string;
  outcome?: EmailOutcome;
  /** The share sheet needs a fresh tap (the first one was used up while the
   *  copy was being made): call this from a button's click to try again. */
  shareAgain?: () => Promise<EmailResult>;
  /** The mail link, so the page can offer to open it again. */
  mailto?: string;
}

/** Said when the share sheet was closed without choosing an app. */
export const EMAIL_SHARE_CLOSED = 'Not sent: the share sheet was closed.';

/**
 * Email the customer their invoice from this device's own mail app (Q6):
 *
 *   1. on a phone, the share sheet: the real PDF goes to Gmail, Outlook or
 *      Mail. The share sheet is opened before anything else is awaited, so it
 *      still counts as the tap that asked for it; if the browser says the tap
 *      was used up, `shareAgain` asks for another tap. Closing the sheet is
 *      "Not sent", logged as failed ('cancelled');
 *   2. on a computer, the mail app with a link to the PDF, which the person
 *      sends from there.
 *
 * Nothing here can tell whether the email itself was sent, so the result
 * never says it was: it says where the PDF or the link went.
 */
export async function sendViaEmailAttachment(a: SendArgs): Promise<EmailResult> {
  const addr = emailAddress(a.email);
  if (!addr) return { ok: false, reason: 'This customer has no valid email address.' };

  let pdfBlob: Blob;
  try {
    pdfBlob = documentPdfBlob(a.pdf);
  } catch (e: any) {
    return { ok: false, reason: e?.message ?? 'Could not prepare the PDF.' };
  }

  // ---- 1. The device share sheet, which attaches the real file -------
  // The Web Share API has no recipient field, so the mail app opens with "To:"
  // blank. The address is copied to the clipboard so it is one paste away, and
  // repeated at the top of the message for when the clipboard is unavailable.
  if (canShareFiles()) {
    const file = new File([pdfBlob], `${safeName(a.docNo)}.pdf`, { type: 'application/pdf' });
    const share = async (): Promise<EmailResult> => {
      // Not awaited before the share: the share must start while the tap counts.
      const copied: Promise<boolean> = (async () => {
        try { await navigator.clipboard.writeText(addr); return true; } catch { return false; }
      })();
      try {
        await (navigator as any).share({
          files: [file],
          title: `${a.kindLabel} ${a.docNo}`,
          text: [
            `To: ${addr}`, '',
            a.customerName ? `Hi ${a.customerName},` : 'Hi,', '',
            `Please find your ${a.kindLabel.toLowerCase()} ${a.docNo} attached.`, '',
            'Thank you for shopping with Energia.',
          ].join('\n'),
        });
      } catch (e: any) {
        if (e?.name === 'AbortError') {
          logSend(a, 'email', addr, null, 'failed', 'cancelled');
          return { ok: false, reason: EMAIL_SHARE_CLOSED };
        }
        if (e?.name === 'NotAllowedError') {
          // Nothing was shown, so nothing is logged: the person is asked to tap again.
          return { ok: false, reason: 'The share sheet did not open. Press Email again.', shareAgain: share };
        }
        logSend(a, 'email', addr, null, 'failed', String(e?.message ?? 'share failed'));
        return { ok: false, reason: `The share sheet could not open${e?.message ? ` (${e.message})` : ''}.` };
      }
      logSend(a, 'email', addr, null, 'sent', 'shared as a file from the device');
      return {
        ok: true, outcome: 'shared',
        reason: (await copied)
          ? `The PDF went to the app you chose. ${addr} was copied: paste it into "To:" and send the email from there.`
          : `The PDF went to the app you chose. Send the email to ${addr} from there.`,
      };
    };
    return share();
  }

  // ---- 2. A link, from the mail app on this computer ------------------
  try {
    const { url, path } = await uploadDocumentPdf(a.storeId, a.docKind, a.docNo, a.pdf);
    const body = [
      a.customerName ? `Hi ${a.customerName},` : 'Hi,', '',
      `Here is your ${a.kindLabel.toLowerCase()} ${a.docNo} from Energia:`,
      url, '',
      'Thank you for shopping with Energia.',
    ].join('\n');
    const mailto = `mailto:${encodeURIComponent(addr)}`
      + `?subject=${encodeURIComponent(`${a.kindLabel} ${a.docNo} — Energia`)}`
      + `&body=${encodeURIComponent(body)}`;
    window.location.href = mailto;
    logSend(a, 'email', addr, path, 'sent', 'link fallback — no server-side sender');
    return {
      ok: true, outcome: 'link', mailto,
      reason: 'Your mail app should open with a link to the PDF; send it from there.',
    };
  } catch (e: any) {
    logSend(a, 'email', addr, null, 'failed', String(e?.message ?? 'link fallback failed'));
    return { ok: false, reason: e?.message ?? 'The invoice could not be sent.' };
  }
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

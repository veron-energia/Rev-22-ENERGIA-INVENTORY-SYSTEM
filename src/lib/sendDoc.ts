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
// Sending the actual file
// ---------------------------------------------------------------------
import { documentPdfBlob, downloadDocumentPdf, PdfDoc } from './invoicePdf';
import { documentImageBlob } from './invoiceImage';

export type DocFormat = 'pdf' | 'image';

/** True when this device can attach a real file to a share. */
export function canShareFiles(): boolean {
  try {
    const nav: any = navigator;
    if (!nav?.canShare || !nav?.share) return false;
    const probe = new File(['x'], 'probe.pdf', { type: 'application/pdf' });
    return !!nav.canShare({ files: [probe] });
  } catch { return false; }
}

async function buildFile(pdf: PdfDoc, format: DocFormat, docNo: string): Promise<File> {
  const safe = docNo.replace(/[^A-Za-z0-9._-]/g, '-');
  if (format === 'image') {
    const blob = await documentImageBlob(pdf);
    return new File([blob], `${safe}.png`, { type: 'image/png' });
  }
  return new File([documentPdfBlob(pdf)], `${safe}.pdf`, { type: 'application/pdf' });
}

export interface ShareDocArgs {
  /** The document content, shared with the PDF and image renderers. */
  pdf: PdfDoc;
  format: DocFormat;
  kindLabel: string;
  docNo: string;
  customerName?: string | null;
  /** Only used by the desktop fallback, to open the right chat. */
  phone?: string | null;
  email?: string | null;
  channelHint?: 'whatsapp' | 'email';
}

/**
 * Share the invoice itself.
 *
 * On a phone this opens the native share sheet with the PDF or image already
 * attached — choosing WhatsApp sends the actual document, not a link. Desktop
 * browsers do not support sharing files, so there the file is downloaded and
 * WhatsApp Web or the mail client is opened for the staff member to attach it;
 * the return value says which happened so the UI can explain.
 */
export async function shareDocumentFile(
  a: ShareDocArgs,
): Promise<{ ok: boolean; shared: boolean; reason?: string }> {
  let file: File;
  try {
    file = await buildFile(a.pdf, a.format, a.docNo);
  } catch (e: any) {
    return { ok: false, shared: false, reason: e?.message ?? 'Could not prepare the document.' };
  }

  const text = [
    a.customerName ? `Hi ${a.customerName},` : 'Hi,',
    '',
    `Here is your ${a.kindLabel.toLowerCase()} ${a.docNo} from Energia.`,
    '',
    'Thank you for shopping with Energia.',
  ].join('\n');

  const nav: any = navigator;
  if (canShareFiles()) {
    try {
      await nav.share({ files: [file], title: `${a.kindLabel} ${a.docNo}`, text });
      return { ok: true, shared: true };
    } catch (e: any) {
      // The user dismissing the share sheet is not an error worth reporting.
      if (e?.name === 'AbortError') return { ok: true, shared: true };
      return { ok: false, shared: false, reason: e?.message ?? 'Sharing was not completed.' };
    }
  }

  // Desktop fallback: save the file, then open the chat or mail draft so the
  // staff member can attach what was just downloaded.
  const url = URL.createObjectURL(file);
  const link = document.createElement('a');
  link.href = url; link.download = file.name;
  document.body.appendChild(link); link.click(); link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 30000);

  if (a.channelHint === 'email') {
    const addr = emailAddress(a.email);
    if (addr) {
      window.location.href = `mailto:${encodeURIComponent(addr)}`
        + `?subject=${encodeURIComponent(`${a.kindLabel} ${a.docNo} — Energia`)}`
        + `&body=${encodeURIComponent(text)}`;
    }
  } else {
    const num = whatsappNumber(a.phone);
    if (num) window.open(`https://wa.me/${num}?text=${encodeURIComponent(text)}`, '_blank', 'noopener');
  }
  return { ok: true, shared: false };
}

/** Save the customer copy locally. */
export async function saveDocumentFile(pdf: PdfDoc, format: DocFormat, docNo: string): Promise<void> {
  const safe = docNo.replace(/[^A-Za-z0-9._-]/g, '-');
  if (format === 'image') {
    const blob = await documentImageBlob(pdf);
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = `${safe}.png`;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 30000);
    return;
  }
  downloadDocumentPdf(pdf, `${safe}.pdf`);
}

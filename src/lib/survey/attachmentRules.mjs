// What a survey attachment may be (419; security audit of 17 Nov 2026, L13).
// Photos are an explicit list, not "any image": SVG is refused, because it can
// carry script. The document types and the 10 MB limit are as they were.

export const MAX_BYTES = 10 * 1024 * 1024;   // 10 MB, the bucket's limit (419)

const IMAGE_BY_EXTENSION = {
  jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', gif: 'image/gif',
  webp: 'image/webp', heic: 'image/heic', heif: 'image/heif',
};
const DOCUMENT_BY_EXTENSION = {
  pdf: 'application/pdf', doc: 'application/msword',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  xls: 'application/vnd.ms-excel', xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  csv: 'text/csv', txt: 'text/plain',
};
const BY_EXTENSION = { ...DOCUMENT_BY_EXTENSION, ...IMAGE_BY_EXTENSION };
const IMAGE_TYPES = new Set(Object.values(IMAGE_BY_EXTENSION));
const DOCUMENT_TYPES = new Set(Object.values(DOCUMENT_BY_EXTENSION));

/** What the file picker offers; the bucket takes these types only (419). */
export const ACCEPT = [
  'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/heic', 'image/heif',
  '.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.heif',
  'application/pdf', '.doc', '.docx', '.xls', '.xlsx', '.csv', '.txt',
].join(',');

export const isImage = (mime) => !!mime && String(mime).toLowerCase().startsWith('image/');

/**
 * The file's type for storage: the browser's, or, when it gives none (some
 * phones for HEIC photos), the one its name says. Null when the bucket would
 * not take it, which includes image/svg+xml and any image type not listed.
 */
export function attachmentType(file) {
  const ext = (String(file?.name ?? '').split('.').pop() || '').toLowerCase();
  const t = String(file?.type || BY_EXTENSION[ext] || '').toLowerCase();
  if (!t) return null;
  return IMAGE_TYPES.has(t) || DOCUMENT_TYPES.has(t) ? t : null;
}

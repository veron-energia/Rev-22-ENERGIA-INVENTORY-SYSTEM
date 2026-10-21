import { supabase } from './supabase';

const BUCKET = 'survey-attachments';
export const MAX_BYTES = 10 * 1024 * 1024;   // 10 MB, the bucket's limit (419)

export const isImage = (mime?: string | null) => !!mime && mime.startsWith('image/');

export const prettySize = (b?: number | null) => {
  if (!b) return '';
  if (b < 1024) return `${b} B`;
  if (b < 1024 * 1024) return `${(b / 1024).toFixed(0)} KB`;
  return `${(b / 1024 / 1024).toFixed(1)} MB`;
};

/** What the file picker offers; the bucket takes these types only (419). */
export const ACCEPT = 'image/*,application/pdf,.doc,.docx,.xls,.xlsx,.csv,.txt,.heic';
const BY_EXTENSION: Record<string, string> = {
  pdf: 'application/pdf', doc: 'application/msword',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  xls: 'application/vnd.ms-excel', xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  csv: 'text/csv', txt: 'text/plain', heic: 'image/heic', heif: 'image/heif', jpg: 'image/jpeg', jpeg: 'image/jpeg',
  png: 'image/png', gif: 'image/gif', webp: 'image/webp',
};
const ALLOWED = new Set(Object.values(BY_EXTENSION).filter(t => !t.startsWith('image/')));

/**
 * The file's type for storage: the browser's, or, when it gives none (some
 * phones for HEIC photos), the one its name says. Null when the bucket would
 * not take it.
 */
export function attachmentType(file: { name: string; type?: string | null }): string | null {
  const ext = (file.name.split('.').pop() || '').toLowerCase();
  const t = (file.type || BY_EXTENSION[ext] || '').toLowerCase();
  if (!t) return null;
  return t.startsWith('image/') || ALLOWED.has(t) ? t : null;
}

/**
 * Uploads one file, then records it. The path is
 * {store_id}/{survey_id}/{uuid}.{ext}: the leading store folder is what the
 * storage rule reads to keep files to their store, and add_survey_attachment
 * records a file only from its survey's own folder, with the size and type
 * storage holds (419). A survey that has no store yet (made before 419) uses
 * the folder 'null', as its earlier files do.
 */
export async function uploadSurveyAttachment(
  storeId: string | null, surveyId: string, file: File, caption?: string,
): Promise<void> {
  if (file.size > MAX_BYTES) throw new Error(`${file.name} is larger than 10 MB.`);
  const type = attachmentType(file);
  if (!type) throw new Error(`${file.name}: only photos, PDF, Word, Excel, CSV and text files can be added.`);

  const ext = (file.name.split('.').pop() || 'bin').toLowerCase().replace(/[^a-z0-9]/g, '');
  const path = `${storeId ?? 'null'}/${surveyId}/${crypto.randomUUID()}.${ext}`;

  const { error: upErr } = await supabase.storage.from(BUCKET).upload(path, file, {
    contentType: type, upsert: false,
  });
  if (upErr) throw upErr;

  const { error: recErr } = await supabase.rpc('add_survey_attachment', {
    p_survey_id: surveyId, p_path: path, p_file_name: file.name,
    p_mime: type, p_size: file.size, p_caption: caption || null,
  });
  // Don't leave an orphaned object if the record failed.
  if (recErr) {
    await supabase.storage.from(BUCKET).remove([path]).catch(() => {});
    throw recErr;
  }
}

/** Short-lived signed URL — the bucket is private, so nothing is readable without one. */
export async function signedUrl(path: string, seconds = 300): Promise<string | null> {
  const { data, error } = await supabase.storage.from(BUCKET).createSignedUrl(path, seconds);
  return error ? null : data?.signedUrl ?? null;
}

/** Removes the record (permission-checked + audited), then the object. */
export async function removeSurveyAttachment(id: string): Promise<void> {
  const { data: path, error } = await supabase.rpc('delete_survey_attachment', { p_id: id });
  if (error) throw error;
  if (path) await supabase.storage.from(BUCKET).remove([path as string]).catch(() => {});
}

export async function downloadAttachment(path: string, fileName: string): Promise<void> {
  const { data, error } = await supabase.storage.from(BUCKET).download(path);
  if (error || !data) throw error ?? new Error('Could not download the file.');
  const url = URL.createObjectURL(data);
  const a = document.createElement('a');
  a.href = url; a.download = fileName;
  a.click();
  URL.revokeObjectURL(url);
}

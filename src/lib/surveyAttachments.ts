import { supabase } from './supabase';

const BUCKET = 'survey-attachments';
export const MAX_BYTES = 10 * 1024 * 1024;   // 10 MB, matches the DB guard

export const isImage = (mime?: string | null) => !!mime && mime.startsWith('image/');

export const prettySize = (b?: number | null) => {
  if (!b) return '';
  if (b < 1024) return `${b} B`;
  if (b < 1024 * 1024) return `${(b / 1024).toFixed(0)} KB`;
  return `${(b / 1024 / 1024).toFixed(1)} MB`;
};

/**
 * Uploads one file, then records it. The path is
 * {store_id}/{survey_id}/{uuid}.{ext} — the leading store folder is what
 * the storage policy reads to enforce store scoping, so it must not change.
 */
export async function uploadSurveyAttachment(
  storeId: string, surveyId: string, file: File, caption?: string,
): Promise<void> {
  if (file.size > MAX_BYTES) throw new Error(`${file.name} is larger than 10 MB.`);

  const ext = (file.name.split('.').pop() || 'bin').toLowerCase().replace(/[^a-z0-9]/g, '');
  const path = `${storeId}/${surveyId}/${crypto.randomUUID()}.${ext}`;

  const { error: upErr } = await supabase.storage.from(BUCKET).upload(path, file, {
    contentType: file.type || 'application/octet-stream', upsert: false,
  });
  if (upErr) throw upErr;

  const { error: recErr } = await supabase.rpc('add_survey_attachment', {
    p_survey_id: surveyId, p_path: path, p_file_name: file.name,
    p_mime: file.type || null, p_size: file.size, p_caption: caption || null,
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

import { supabase } from './supabase';
import { MAX_BYTES, ACCEPT, isImage, attachmentType } from './survey/attachmentRules.mjs';

const BUCKET = 'survey-attachments';

// The rules (types, the 10 MB limit) live in survey/attachmentRules.mjs, so a
// unit test can read them without the Supabase client. L13: photos are an
// explicit list, and SVG is refused.
export { MAX_BYTES, ACCEPT, isImage, attachmentType };

export const prettySize = (b?: number | null) => {
  if (!b) return '';
  if (b < 1024) return `${b} B`;
  if (b < 1024 * 1024) return `${(b / 1024).toFixed(0)} KB`;
  return `${(b / 1024 / 1024).toFixed(1)} MB`;
};

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

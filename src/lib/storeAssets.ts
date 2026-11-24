import { supabase } from './supabase';

// Uploads an image to the public 'store-assets' bucket and returns its public
// URL. Each upload is a new file under the store's own folder, never a
// replacement of an old one: from migration 532 (security audit of 17 Nov
// 2026, M7) no login may overwrite or remove a file there, and only an Owner,
// or a Manager of that store, may add one. A store's QR code or logo therefore
// changes only when the store's own address for it changes, which the audit
// log records with the old and the new address. Old files stay where they are,
// so an invoice copy that names one keeps its picture.
export async function uploadStoreAsset(storeId: string, field: string, file: File): Promise<string> {
  const given = (file.name.split('.').pop() || '').toLowerCase();
  const ext = /^[a-z0-9]{1,5}$/.test(given) ? given : 'png';
  const path = `${storeId}/${field}-${crypto.randomUUID()}.${ext}`;
  const { error } = await supabase.storage.from('store-assets').upload(path, file, {
    upsert: false, contentType: file.type || 'image/png',
  });
  if (error) throw error;
  const { data } = supabase.storage.from('store-assets').getPublicUrl(path);
  return data.publicUrl;
}

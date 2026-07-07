import { supabase } from './supabase';

// Uploads an image to the public 'store-assets' bucket and returns its public
// URL. Path is namespaced by store id + field so re-uploads overwrite cleanly.
export async function uploadStoreAsset(storeId: string, field: string, file: File): Promise<string> {
  const ext = (file.name.split('.').pop() || 'png').toLowerCase();
  const path = `${storeId}/${field}.${ext}`;
  const { error } = await supabase.storage.from('store-assets').upload(path, file, {
    upsert: true, contentType: file.type || 'image/png',
  });
  if (error) throw error;
  const { data } = supabase.storage.from('store-assets').getPublicUrl(path);
  // Cache-bust so a replaced image shows immediately.
  return `${data.publicUrl}?v=${Date.now()}`;
}

import { supabase } from './supabase';
import { storeAssetRefusal, storeAssetType, storeAssetExtension } from './storeAssetRules.mjs';

// L13 (security audit of 17 Nov 2026): only PNG, JPEG or WebP, up to 5 MB. The
// bucket holds the same limits; the page refuses first, with a plain sentence.
export { STORE_ASSET_ACCEPT } from './storeAssetRules.mjs';

// Uploads an image to the public 'store-assets' bucket and returns its public
// URL. Each upload is a new file under the store's own folder, never a
// replacement of an old one: from migration 532 (security audit of 17 Nov
// 2026, M7) no login may overwrite or remove a file there, and only an Owner,
// or a Manager of that store, may add one. A store's QR code or logo therefore
// changes only when the store's own address for it changes, which the audit
// log records with the old and the new address. Old files stay where they are,
// so an invoice copy that names one keeps its picture.
export async function uploadStoreAsset(storeId: string, field: string, file: File): Promise<string> {
  const refusal = storeAssetRefusal(file);
  if (refusal) throw new Error(refusal);
  const type = storeAssetType(file)!;
  const ext = storeAssetExtension(type)!;
  const path = `${storeId}/${field}-${crypto.randomUUID()}.${ext}`;
  const { error } = await supabase.storage.from('store-assets').upload(path, file, {
    upsert: false, contentType: type,
  });
  if (error) throw error;
  const { data } = supabase.storage.from('store-assets').getPublicUrl(path);
  return data.publicUrl;
}

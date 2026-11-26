// What a store's logo or QR image may be (security audit of 17 Nov 2026, L13).
// The public 'store-assets' bucket takes PNG, JPEG and WebP up to 5 MB; the page
// refuses anything else before it uploads, so the person reads why. SVG is not
// on the list: it can carry script, and the bucket is public.

export const STORE_ASSET_MAX_BYTES = 5 * 1024 * 1024;
export const STORE_ASSET_ACCEPT = 'image/png,image/jpeg,image/webp,.png,.jpg,.jpeg,.webp';
export const STORE_ASSET_TYPES = ['image/png', 'image/jpeg', 'image/webp'];
const BY_EXTENSION = { png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', webp: 'image/webp' };
const EXTENSION_OF = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp' };

/** The image type to store: the browser's, or the one the name says when it gives none. Null when not allowed. */
export function storeAssetType(file) {
  const ext = (String(file?.name ?? '').split('.').pop() || '').toLowerCase();
  const t = String(file?.type || BY_EXTENSION[ext] || '').toLowerCase();
  return STORE_ASSET_TYPES.includes(t) ? t : null;
}

/** The file extension that goes with an allowed type. */
export function storeAssetExtension(type) {
  return EXTENSION_OF[type] ?? null;
}

/** A plain sentence saying why the file is refused, or null when it may be uploaded. */
export function storeAssetRefusal(file) {
  if (!storeAssetType(file)) return 'Only PNG, JPEG or WebP pictures can be uploaded here.';
  if (file.size > STORE_ASSET_MAX_BYTES) return 'That picture is larger than 5 MB. Choose a smaller one.';
  return null;
}

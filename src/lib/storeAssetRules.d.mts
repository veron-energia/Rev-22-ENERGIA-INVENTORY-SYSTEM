export const STORE_ASSET_MAX_BYTES: number;
export const STORE_ASSET_ACCEPT: string;
export const STORE_ASSET_TYPES: string[];
export function storeAssetType(file: { name?: string; type?: string | null }): string | null;
export function storeAssetExtension(type: string): string | null;
export function storeAssetRefusal(file: { name?: string; type?: string | null; size: number }): string | null;

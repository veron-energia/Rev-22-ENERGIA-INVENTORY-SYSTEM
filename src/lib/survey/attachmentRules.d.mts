export const MAX_BYTES: number;
export const ACCEPT: string;
export const isImage: (mime?: string | null) => boolean;
export function attachmentType(file: { name: string; type?: string | null }): string | null;

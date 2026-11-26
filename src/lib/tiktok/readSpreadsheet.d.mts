export const MAX_IMPORT_FILE_BYTES: number;
export const MAX_IMPORT_ROWS: number;
export function FILE_TOO_BIG_MESSAGE(name: string): string;
export function TOO_MANY_ROWS_MESSAGE(name: string): string;
export function NOT_REAL_XLSX_MESSAGE(name: string): string;
export function WRONG_FILE_TYPE_MESSAGE(name: string): string;
export function repairWorksheetRange(ws: Record<string, unknown>): void;
export function readGridsFromFile(file: File): Promise<{ name: string; grid: string[][] }[]>;

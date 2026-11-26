// Reading a TikTok order / settlement file (.xlsx or .csv) into text grids.
//
// SECURITY (audit M15). The xlsx library is only ever handed a file the user
// chose, but a crafted file could still hurt it, so before parsing the file is
// refused if it is too big, and after parsing if it has too many rows. The
// library is SheetJS 0.20.3 (the first release without the prototype-pollution
// and ReDoS flaws); formulas are never evaluated, only the cached text is read.

import * as XLSX from 'xlsx';
import Papa from 'papaparse';

export const MAX_IMPORT_FILE_BYTES = 10 * 1024 * 1024; // 10 MB
export const MAX_IMPORT_ROWS = 20000;                  // per sheet

export const FILE_TOO_BIG_MESSAGE = (name) =>
  `"${name}" is larger than 10 MB, which is more than a TikTok order or settlement export should be. Please export a shorter date range and try again.`;
export const TOO_MANY_ROWS_MESSAGE = (name) =>
  `"${name}" has more than 20,000 rows, which is more than a TikTok order or settlement export should have. Please export a shorter date range and try again.`;

export const NOT_REAL_XLSX_MESSAGE = (name) =>
  `"${name}" is not a real .xlsx file. Please download the export from TikTok again, as .xlsx or .csv, and try again.`;
export const WRONG_FILE_TYPE_MESSAGE = (name) =>
  `"${name}" is not an .xlsx or .csv file. Only TikTok's .xlsx or .csv exports can be imported.`;

// REGRESSION GUARD. TikTok settlement exports (and XLSX files written by WPS
// Office) can carry a STALE OR WRONG worksheet dimension: one real file held
// rows 1-12 but declared "A1:BG2", and sheet_to_json() silently dropped ten
// rows. So !ref is recomputed from the cell addresses actually present.
// Keys beginning with "!" are metadata. (This relies on the default sparse
// sheet, so dense mode is NOT used.)
export function repairWorksheetRange(ws) {
  const addresses = Object.keys(ws).filter(
    key => !key.startsWith('!') && /^[A-Z]+[1-9][0-9]*$/.test(key)
  );
  if (addresses.length === 0) return;
  let minRow = Infinity, minCol = Infinity, maxRow = -1, maxCol = -1;
  for (const address of addresses) {
    const cell = XLSX.utils.decode_cell(address);
    minRow = Math.min(minRow, cell.r);
    minCol = Math.min(minCol, cell.c);
    maxRow = Math.max(maxRow, cell.r);
    maxCol = Math.max(maxCol, cell.c);
  }
  if (Number.isFinite(minRow) && Number.isFinite(minCol) && maxRow >= 0 && maxCol >= 0) {
    ws['!ref'] = XLSX.utils.encode_range({ r: minRow, c: minCol }, { r: maxRow, c: maxCol });
  }
}

// `file` is a File (or anything with name, size, text(), arrayBuffer()).
// Returns [{ name, grid }]; throws an Error with a plain sentence when refused.
export async function readGridsFromFile(file) {
  if (file.size > MAX_IMPORT_FILE_BYTES) throw new Error(FILE_TOO_BIG_MESSAGE(file.name));

  if (file.name.toLowerCase().endsWith('.csv')) {
    const text = await file.text();
    // dynamicTyping stays OFF: every cell is a string, IDs stay exact.
    const parsed = Papa.parse(text, { skipEmptyLines: 'greedy' });
    if (parsed.data.length > MAX_IMPORT_ROWS) throw new Error(TOO_MANY_ROWS_MESSAGE(file.name));
    return [{ name: 'CSV', grid: parsed.data.map(r => r.map(c => String(c ?? ''))) }];
  }

  // XLSX.read accepts about thirty formats (HTML tables, SYLK, plain text, even
  // random bytes), so only a real .xlsx, which is a zip (50 4B 03 04), gets there.
  if (!file.name.toLowerCase().endsWith('.xlsx')) throw new Error(WRONG_FILE_TYPE_MESSAGE(file.name));
  const buf = await file.arrayBuffer();
  const head = new Uint8Array(buf, 0, Math.min(4, buf.byteLength));
  if (head.length < 4 || head[0] !== 0x50 || head[1] !== 0x4b || head[2] !== 0x03 || head[3] !== 0x04) {
    throw new Error(NOT_REAL_XLSX_MESSAGE(file.name));
  }
  // cellText keeps the formatted text; formulas are not evaluated (cellFormula
  // off, cached values only); dates stay as the file's own text (cellDates off,
  // raw:false below). sheetRows is NOT used: it does not bound memory (the
  // library inflates the whole sheet first) and it would silently drop rows
  // after an empty row at the limit. The 10 MB check above is the bound.
  const wb = XLSX.read(buf, {
    type: 'array', cellText: true, cellFormula: false, cellHTML: false, cellDates: false,
  });
  return wb.SheetNames.map(name => {
    const ws = wb.Sheets[name];
    repairWorksheetRange(ws);
    // Count by position, so blank rows count: the last row of the (repaired)
    // range, not the number of filled rows.
    if (ws['!ref'] && XLSX.utils.decode_range(ws['!ref']).e.r + 1 > MAX_IMPORT_ROWS) {
      throw new Error(TOO_MANY_ROWS_MESSAGE(file.name));
    }
    // raw:false -> formatted text for every cell, so big IDs keep all digits.
    const grid = XLSX.utils.sheet_to_json(ws, { header: 1, raw: false, defval: '' });
    if (grid.length > MAX_IMPORT_ROWS) throw new Error(TOO_MANY_ROWS_MESSAGE(file.name));
    return { name, grid: grid.map(r => r.map(c => String(c ?? ''))) };
  });
}

// Reading a TikTok file with SheetJS 0.20.3: size limit, row limit, and a
// made-up small workbook that still maps (audit M15). All data is invented.
//
// Run: node --test scripts/tiktok/tests/read-spreadsheet-m15.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import * as XLSX from 'xlsx';
import {
  readGridsFromFile, MAX_IMPORT_FILE_BYTES, MAX_IMPORT_ROWS, FILE_TOO_BIG_MESSAGE, TOO_MANY_ROWS_MESSAGE, NOT_REAL_XLSX_MESSAGE, WRONG_FILE_TYPE_MESSAGE,
} from '../../../src/lib/tiktok/readSpreadsheet.mjs';

const fileFrom = (name, bytes, sizeOverride) => ({
  name, size: sizeOverride ?? bytes.length,
  arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength),
  text: async () => Buffer.from(bytes).toString('utf8'),
});
const xlsxBytes = (aoa, edit) => {
  const ws = XLSX.utils.aoa_to_sheet(aoa);
  if (edit) edit(ws);
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, 'Order details');
  return new Uint8Array(XLSX.write(wb, { type: 'array', bookType: 'xlsx' }));
};

// The writer trusts !ref, so a wrong dimension is put into the file's XML afterwards.
function patchDimension(good, ref) {
  const py = 'import sys,zipfile,io,re\nref=sys.argv[1].encode()\nz=zipfile.ZipFile(io.BytesIO(sys.stdin.buffer.read()))\no=io.BytesIO()\nw=zipfile.ZipFile(o,"w",zipfile.ZIP_DEFLATED)\n' +
    'for n in z.namelist():\n d=z.read(n)\n if n=="xl/worksheets/sheet1.xml":\n  d=re.sub(rb\'<dimension ref="[^"]*"\',b\'<dimension ref="\'+ref+b\'"\',d)\n w.writestr(n,d)\nw.close()\nsys.stdout.buffer.write(o.getvalue())';
  const out = spawnSync('python3', ['-I', '-c', py, ref], { input: good, maxBuffer: 1 << 28 });
  assert.equal(out.status, 0, String(out.stderr));
  return new Uint8Array(out.stdout);
}

test('the library is 0.20.3', () => assert.equal(XLSX.version, '0.20.3'));

test('a small made-up workbook is read as text, long IDs keep every digit', async () => {
  const bytes = xlsxBytes([['Order ID', 'Total'], ['5800000000000000001', 12.5], ['5800000000000000002', 3]],
    ws => { ws.A2.t = 's'; ws.A3.t = 's'; });
  const [sheet] = await readGridsFromFile(fileFrom('orders.xlsx', bytes));
  assert.equal(sheet.name, 'Order details');
  assert.deepEqual(sheet.grid, [['Order ID', 'Total'], ['5800000000000000001', '12.5'], ['5800000000000000002', '3']]);
});

test('a wrong declared range is repaired (the 12-rows-declared-as-2 regression)', async () => {
  const rows = [['Order ID', 'Total']].concat(Array.from({ length: 11 }, (_, i) => [`ID${i}`, String(i)]));
  const bad = patchDimension(Buffer.from(xlsxBytes(rows)), 'A1:BG2');
  // sanity: without the repair the library itself would stop at row 2
  const raw = XLSX.read(bad, { type: 'array' });
  assert.equal(XLSX.utils.sheet_to_json(raw.Sheets['Order details'], { header: 1 }).length, 2);
  const [sheet] = await readGridsFromFile(fileFrom('wps.xlsx', bad));
  assert.equal(sheet.grid.length, 12);
});

test('a CSV is read as text', async () => {
  const [sheet] = await readGridsFromFile(fileFrom('o.csv', Buffer.from('Order ID,Total\n5800000000000000001,12.5\n')));
  assert.deepEqual(sheet.grid, [['Order ID', 'Total'], ['5800000000000000001', '12.5']]);
});

test('a file over 10 MB is refused before it is read', async () => {
  let read = false;
  const f = { name: 'big.xlsx', size: MAX_IMPORT_FILE_BYTES + 1, arrayBuffer: async () => { read = true; return new ArrayBuffer(0); }, text: async () => { read = true; return ''; } };
  await assert.rejects(readGridsFromFile(f), { message: FILE_TOO_BIG_MESSAGE('big.xlsx') });
  assert.equal(read, false);
  await assert.rejects(readGridsFromFile({ ...f, name: 'big.csv' }), { message: FILE_TOO_BIG_MESSAGE('big.csv') });
});

test('exactly 20,000 rows is read; one more is refused (xlsx and csv)', async () => {
  const make = n => [['Order ID']].concat(Array.from({ length: n - 1 }, (_, i) => [`o${i}`]));
  const [ok] = await readGridsFromFile(fileFrom('ok.xlsx', xlsxBytes(make(MAX_IMPORT_ROWS))));
  assert.equal(ok.grid.length, MAX_IMPORT_ROWS);
  await assert.rejects(readGridsFromFile(fileFrom('many.xlsx', xlsxBytes(make(MAX_IMPORT_ROWS + 1)))), { message: TOO_MANY_ROWS_MESSAGE('many.xlsx') });
  const csv = make(MAX_IMPORT_ROWS + 1).map(r => r[0]).join('\n');
  await assert.rejects(readGridsFromFile(fileFrom('many.csv', Buffer.from(csv))), { message: TOO_MANY_ROWS_MESSAGE('many.csv') });
});

test('the export helpers still write a workbook that reads back (made-up rows)', () => {
  const ws = XLSX.utils.json_to_sheet([{ A: 'x', B: 1 }, { A: 'y', B: 2 }], { header: ['A', 'B'] });
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, ws, 'Daily Payments');
  const back = XLSX.read(XLSX.write(wb, { type: 'array', bookType: 'xlsx' }), { type: 'array' });
  assert.deepEqual(XLSX.utils.sheet_to_json(back.Sheets['Daily Payments']), [{ A: 'x', B: 1 }, { A: 'y', B: 2 }]);
});

// 20,000 rows, then an EMPTY row 20,001, then data at row 20,002.
const gapFile = () => {
  const rows = [['Order ID']].concat(Array.from({ length: MAX_IMPORT_ROWS - 1 }, (_, i) => [`o${i}`]));
  return xlsxBytes(rows, ws => {
    ws.A20002 = { t: 's', v: 'late' };
    ws['!ref'] = `A1:A${MAX_IMPORT_ROWS + 2}`;
  });
};

test('(a) an empty row 20,001 with data at row 20,002 is refused, not silently cut', async () => {
  await assert.rejects(readGridsFromFile(fileFrom('gap.xlsx', gapFile())), { message: TOO_MANY_ROWS_MESSAGE('gap.xlsx') });
});

test('(b) the same file with a small declared dimension is refused too', async () => {
  const bad = patchDimension(Buffer.from(gapFile()), 'A1:B2');
  await assert.rejects(readGridsFromFile(fileFrom('gap2.xlsx', bad)), { message: TOO_MANY_ROWS_MESSAGE('gap2.xlsx') });
});

// Only a real .xlsx (a zip: 50 4B 03 04) or a .csv is read.
const textFile = (name, text) => fileFrom(name, Buffer.from(text));
test('a file named .xlsx that is not a zip is refused (html, csv text, sylk, random bytes, under 4 bytes)', async () => {
  const cases = {
    'table.xlsx': textFile('table.xlsx', '<html><body><table><tr><td>Order ID</td></tr><tr><td>1</td></tr></table></body></html>'),
    'text.xlsx': textFile('text.xlsx', 'Order ID,Total\n1,2\n'),
    'old.xlsx': textFile('old.xlsx', 'ID;PWXL;N;E\nC;X1;Y1;K"Order ID"\nE\n'),
    'noise.xlsx': fileFrom('noise.xlsx', new Uint8Array(Array.from({ length: 200 }, (_, i) => (i * 37 + 11) % 256))),
    'tiny.xlsx': fileFrom('tiny.xlsx', new Uint8Array([0x50, 0x4b, 0x03])),
    'empty.xlsx': fileFrom('empty.xlsx', new Uint8Array(0)),
  };
  for (const [name, f] of Object.entries(cases)) {
    await assert.rejects(readGridsFromFile(f), { message: NOT_REAL_XLSX_MESSAGE(name) }, name);
  }
});

test('any other name is refused by name, even a real xlsx renamed .xls', async () => {
  const real = xlsxBytes([['Order ID'], ['1']]);
  for (const name of ['orders.xls', 'orders.xlsm', 'orders', 'orders.xlsx.exe', 'orders.html']) {
    await assert.rejects(readGridsFromFile(fileFrom(name, real)), { message: WRONG_FILE_TYPE_MESSAGE(name) }, name);
  }
});

test('a real xlsx is read, also with an upper-case .XLSX name', async () => {
  const real = xlsxBytes([['Order ID'], ['1']]);
  for (const name of ['orders.xlsx', 'ORDERS.XLSX']) {
    const [sheet] = await readGridsFromFile(fileFrom(name, real));
    assert.deepEqual(sheet.grid, [['Order ID'], ['1']]);
  }
});

test('an empty extra sheet that declares a large range is read as empty, not refused', async () => {
  const wb = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet([['Order ID', 'Total'], ['1', '2']]), 'Order details');
  XLSX.utils.book_append_sheet(wb, { '!ref': 'A1:C30000' }, 'Empty');
  const bytes = new Uint8Array(XLSX.write(wb, { type: 'array', bookType: 'xlsx' }));
  // sanity: the written file really declares the large range on the cell-less sheet
  assert.equal(XLSX.read(bytes, { type: 'array' }).Sheets['Empty']['!ref'], 'A1:C30000');
  const sheets = await readGridsFromFile(fileFrom('two-sheets.xlsx', bytes));
  assert.deepEqual(sheets.map(s => [s.name, s.grid.length]), [['Order details', 2], ['Empty', 0]]);
});

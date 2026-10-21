// 419 (CUSTOMERS-16): the signed PDF of the QR form.
//
//   - a value the PDF's built-in font cannot show (a Chinese name) is drawn
//     as a picture, so it is printed rather than garbled;
//   - without a way to draw it (no canvas), such letters print as "?";
//   - long values wrap inside their space instead of running off the page.
//
// Run: node --test scripts/survey/tests/survey-pdf.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const dir = await mkdtemp(join(tmpdir(), 'energia-survey-pdf-'));
await build({
  entryPoints: ['src/lib/surveyPdf.ts'], outfile: join(dir, 'pdf.mjs'),
  bundle: true, format: 'esm', platform: 'node', logLevel: 'silent',
});
const { buildSurveyPdf, fitsStandardFont } = await import(pathToFileURL(join(dir, 'pdf.mjs')).href);

// A 1x1 PNG: what a painter would hand back.
const DOT = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
const BASE = {
  store_name: 'Fixture Store', full_name: 'Mei Ling Testtan', phone: '+61491570006', email: 'mei@example.com',
  date_of_birth: '1980-01-02', sex: 'female', signed_date: '2026-10-19', symptoms: [],
  has_medical_condition: false, drinks_alcohol: null, smokes: true, on_treatment: false,
};
const pdfText = b64 => Buffer.from(b64, 'base64').toString('latin1');
const images = s => (s.match(/\/Subtype \/Image/g) ?? []).length;

test('the built-in font covers Latin text, and not Chinese', () => {
  assert.equal(fitsStandardFont('Mei Ling Tan — café “x” •'), true);
  assert.equal(fitsStandardFont('王美玲'), false);
});

test('a Chinese name is drawn as a picture by the painter', () => {
  const calls = [];
  const painter = (text, o) => { calls.push({ text, ...o }); return { dataUrl: DOT, widthMm: 20, heightMm: 4 }; };
  const plain = pdfText(buildSurveyPdf(BASE, { painter }));
  assert.equal(calls.length, 0, 'Latin text needs no picture');
  const cjk = pdfText(buildSurveyPdf({ ...BASE, full_name: '王美玲 Testwang', event_name: '健康讲座' }, { painter }));
  assert.deepEqual(calls.map(c => c.text).sort(), ['Fixture Store · 健康讲座', '王美玲 Testwang'].sort());
  assert.ok(calls.every(c => c.maxWidthMm > 0 && c.sizePt > 0));
  assert.ok(images(cjk) > images(plain), 'the name is in the PDF as an image');
});

test('without a painter the letters print as "?" rather than garbled', () => {
  const out = pdfText(buildSurveyPdf({ ...BASE, full_name: '王美玲 Testwang' }, { painter: () => null }));
  assert.ok(out.includes('??? Testwang'), 'question marks in place of the letters it cannot show');
});

test('long values wrap inside their space', () => {
  const long = 'Lower back pain after lifting boxes at work, worse in the morning and after long drives, '.repeat(4);
  const out = pdfText(buildSurveyPdf({ ...BASE, on_treatment: true, treatment_list: long, others_text: long,
    occupation: 'Senior warehouse operations and logistics coordinator for the eastern region',
    symptoms: [{ category: 'Pain', label: 'Back', duration_text: 'Since the accident in March two years ago, on and off' }] },
    { painter: () => null }));
  // Every line of text stays on the page: no text drawn past the right edge
  // (x > 196 mm = 555.6 pt), which is where an unwrapped value would start
  // running off.
  const xs = [...out.matchAll(/BT\s*\/F\d+ [\d.]+ Tf\s*[\d.]+ TL\s*[^\n]*\n?([\d.]+) ([\d.]+) Td/g)].map(m => Number(m[1]));
  assert.ok(xs.length > 0, 'the PDF has text');
  assert.ok(xs.every(x => x <= 556), `text starts inside the page (${Math.max(...xs)})`);
  assert.ok(out.includes('(Lower back pain after lifting boxes at work, worse in the morning and after long'), 'the list is wrapped');
});

test.after(async () => { await rm(dir, { recursive: true, force: true }); });

// The send log is written when a document is sent (src/lib/sendDoc.ts, 389).
//
// logSend once fired its call with "void supabase.rpc(...)". The Supabase
// client only sends a request when then() is called on it, so the call was
// never made and document_sends stayed empty. Here the real sendDoc.ts runs on
// the real @supabase/supabase-js client; only fetch is faked, so every request
// the client would put on the wire is seen. The PDF builders are stubbed. Every
// name, number and id below is invented.
//
// It checks that a WhatsApp send logs itself with all nine arguments the live
// record_document_send(text,text,text,uuid,uuid,text,text,text,text) takes;
// that the send does not wait for the log; that a log the database refuses
// (production's 42703 before 389) or a network failure neither throws nor
// turns the send into a failure; that a failed upload is logged as 'failed'
// with its reason; and that the email link fallback logs itself too.
//
// 407: each send is filed under a name of its own and never replaces a file
// (upsert off), so a link a customer holds cannot be pointed at another PDF.
// The path logged is the one uploaded and signed, and two sends of the same
// invoice use two names.
//
// B16 (AFTER-11, AFTER-M3, Q6): WhatsApp's window is opened in the click, and
// only a window really obtained is logged 'sent'; a blocked one is 'failed'.
// Email goes from the device's own mail app: a closed share sheet is "Not
// sent" and logged as failed, and nothing says a PDF was attached or emailed.
//
// Run: node --test scripts/invoices/tests/send-log.test.mjs
import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const REPO = fileURLToPath(new URL('../../../', import.meta.url));

const built = await build({
  stdin: { contents: `export * from './src/lib/sendDoc';`, resolveDir: REPO, loader: 'ts' },
  bundle: true, write: false, format: 'esm', platform: 'browser', logLevel: 'silent',
  define: { 'import.meta.env': '{"VITE_INVOICE_EMAIL":"off"}' },
  plugins: [{ name: 'stubs', setup(b) {
    b.onResolve({ filter: /^\.\/(supabase|invoicePdf|invoiceImage)$/ }, a =>
      a.importer.endsWith('sendDoc.ts') ? { path: a.path.slice(2), namespace: 'stub' } : undefined);
    // The real client, with fetch handed to the test.
    b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js', resolveDir: REPO, contents: `
      import { createClient } from '@supabase/supabase-js';
      export const supabase = createClient('https://db.invalid', 'anon-key-for-tests', {
        auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
        global: { fetch: (...a) => globalThis.__fetch(...a) },
      });` }));
    b.onLoad({ filter: /^invoicePdf$/, namespace: 'stub' }, () => ({ loader: 'js', contents: `
      export const documentPdfBlob = () => new Blob(['%PDF-fixture'], { type: 'application/pdf' });
      export const downloadDocumentPdf = () => {};` }));
    b.onLoad({ filter: /^invoiceImage$/, namespace: 'stub' }, () => ({ loader: 'js',
      contents: 'export const documentImageBlob = async () => new Blob([]);' }));
  } }],
});
const { sendViaWhatsAppLink, sendViaEmailAttachment, WHATSAPP_BLOCKED, EMAIL_SHARE_CLOSED } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// ── fixture ────────────────────────────────────────────────────────────────
const DOC = {
  pdf: {}, kindLabel: 'Invoice', docNo: 'INV-TEST-0001', docKind: 'invoice',
  docId: '00000000-0000-4000-8000-000000000001', storeId: 'store-test',
  customerId: '00000000-0000-4000-8000-000000000002', customerName: 'Ana Test',
  phone: '+65 9123 4567', email: 'ana.test@tests.invalid',
};
// store / kind / document number, then a name no earlier send used.
const PATH_SHAPE = /^store-test\/invoice\/INV-TEST-0001-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.pdf$/;
const UPLOAD = 'https://db.invalid/storage/v1/object/invoice-pdfs/';
const SIGN = 'https://db.invalid/storage/v1/object/sign/invoice-pdfs/';
const RPC = 'https://db.invalid/rest/v1/rpc/record_document_send';
const NINE = ['p_doc_kind', 'p_doc_no', 'p_channel', 'p_doc_id', 'p_customer_id', 'p_sent_to', 'p_pdf_path', 'p_status', 'p_error'];

let requests, events, warnings, unhandled, rpcReply, uploadReply;
const json = (status, body) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
const onUnhandled = e => unhandled.push(e);
const consoleWarn = console.warn;

beforeEach(() => {
  requests = []; events = []; warnings = []; unhandled = [];
  rpcReply = () => json(200, '00000000-0000-4000-8000-0000000000aa');
  uploadReply = path => json(200, { Id: 'obj-test', Key: `invoice-pdfs/${path}` });
  globalThis.__fetch = async (input, init = {}) => {
    const url = String(input instanceof Request ? input.url : input);
    const body = typeof init.body === 'string' ? init.body : null;
    const headers = new Headers(init.headers ?? {});
    requests.push({ method: init.method ?? 'GET', url, body, upsert: headers.get('x-upsert') });
    if (url === RPC) { events.push('log requested'); return rpcReply(); }
    if (url.startsWith(SIGN)) {
      return json(200, { signedURL: `/object/sign/invoice-pdfs/${decodeURIComponent(url.slice(SIGN.length))}?token=t` }); }
    if (url.startsWith(UPLOAD)) return uploadReply(decodeURIComponent(url.slice(UPLOAD.length)));
    return json(404, { message: `unexpected request ${url}` });
  };
  // B16 (AFTER-11): window.open hands back a window, or null when a pop-up
  // blocker stops it (window.blockPopups).
  globalThis.window = {
    open: url => {
      if (window.blockPopups) return null;
      const w = fakeWindow();
      if (url) { events.push('chat opened'); window.opened = url; }
      return w;
    },
    location: { set href(v) { events.push('mail opened'); window.mailto = v; } },
  };
  console.warn = (...a) => warnings.push(a.map(String).join(' '));
  process.on('unhandledRejection', onUnhandled);
});
afterEach(() => {
  console.warn = consoleWarn;
  process.off('unhandledRejection', onUnhandled);
});

/** A window as window.open returns one: it records where it is sent and whether it was closed. */
function fakeWindow() {
  const w = { closed: false, opener: 'this page', sentTo: null, document: { title: '', body: { textContent: '' } },
    close() { w.closed = true; events.push('window closed'); },
    location: { set href(v) { w.sentTo = v; events.push('chat opened'); window.opened = v; } } };
  return w;
}
/** The client resolves the session before it fetches, so give it a few turns. */
async function settle() { for (let i = 0; i < 20; i++) await new Promise(r => setTimeout(r, 0)); }
const logRequests = () => requests.filter(r => r.url === RPC);
const uploads = () => requests.filter(r => r.url.startsWith(UPLOAD));
/** The one path uploaded: a new file, never a replacement, filed under its store. */
function uploadedPath() {
  const up = uploads();
  assert.equal(up.length, 1, 'one upload');
  assert.equal(up[0].method, 'POST', 'a new file, not a replacement');
  assert.equal(up[0].upsert, 'false', 'never replaces a file');
  const path = decodeURIComponent(up[0].url.slice(UPLOAD.length));
  assert.match(path, PATH_SHAPE);
  return path;
}

// ── checks ─────────────────────────────────────────────────────────────────
test('a WhatsApp send logs itself, after the chat opens, with the nine arguments record_document_send takes', async () => {
  const res = await sendViaWhatsAppLink(DOC);
  await settle();
  assert.deepEqual(res, { ok: true });
  const logs = logRequests();
  assert.equal(logs.length, 1, 'exactly one log request goes out');
  assert.equal(logs[0].method, 'POST');
  const body = JSON.parse(logs[0].body);
  assert.deepEqual(Object.keys(body).sort(), [...NINE].sort(), 'all nine named arguments, so only the 9-argument function matches');
  assert.deepEqual(body, {
    p_doc_kind: 'invoice', p_doc_no: 'INV-TEST-0001', p_channel: 'whatsapp',
    p_doc_id: DOC.docId, p_customer_id: DOC.customerId,
    p_sent_to: '6591234567', p_pdf_path: uploadedPath(), p_status: 'sent', p_error: null,
  });
  assert.deepEqual(events, ['chat opened', 'log requested']);
  assert.deepEqual(warnings, []);
});

test('the send does not wait for the log', async () => {
  const pending = deferred();
  rpcReply = () => pending.promise;
  const res = await sendViaWhatsAppLink(DOC);
  assert.deepEqual(res, { ok: true }, 'the send has returned while the log is still unanswered');
  await settle();
  assert.equal(logRequests().length, 1, 'and the log request is on its way');
  pending.resolve(json(200, '00000000-0000-4000-8000-0000000000aa'));
  await settle();
  assert.deepEqual(warnings, []);
});

test('a log the database refuses (42703, production before 389) is not a failed send', async () => {
  rpcReply = () => json(400, { code: '42703', details: null, hint: null,
    message: 'column "status" of relation "document_sends" does not exist' });
  const res = await sendViaWhatsAppLink(DOC);
  await settle();
  assert.deepEqual(res, { ok: true });
  assert.equal(logRequests().length, 1);
  assert.deepEqual(warnings, ['The send was not logged: column "status" of relation "document_sends" does not exist']);
  assert.deepEqual(unhandled, []);
});

test('a network failure on the log is not a failed send either', async () => {
  rpcReply = () => { throw new TypeError('Failed to fetch'); };
  const res = await sendViaWhatsAppLink(DOC);
  await settle();
  assert.deepEqual(res, { ok: true });
  assert.equal(logRequests().length, 1, 'tried once (the client does not retry a POST)');
  assert.equal(warnings.length, 1);
  assert.match(warnings[0], /^The send was not logged: .*Failed to fetch/);
  assert.deepEqual(unhandled, []);
});

test('a failed upload is logged as failed, with its reason, and no chat opens', async () => {
  uploadReply = () => json(400, { statusCode: '400', error: 'Bad Request', message: 'upload refused (test)' });
  const res = await sendViaWhatsAppLink(DOC);
  await settle();
  assert.equal(res.ok, false);
  assert.match(res.reason, /^Could not upload the PDF: /);
  const logs = logRequests();
  assert.equal(logs.length, 1);
  const body = JSON.parse(logs[0].body);
  assert.equal(body.p_status, 'failed');
  assert.equal(body.p_pdf_path, null);
  assert.equal(body.p_error, res.reason);
  assert.deepEqual(events, ['log requested']);
});

test('the email link fallback logs itself too', async () => {
  // VITE_INVOICE_EMAIL=off skips the edge function, and Node cannot share
  // files, so this goes straight to the link.
  const res = await sendViaEmailAttachment(DOC);
  await settle();
  assert.equal(res.ok, true);
  assert.equal(res.outcome, 'link');
  const logs = logRequests();
  assert.equal(logs.length, 1);
  assert.deepEqual(JSON.parse(logs[0].body), {
    p_doc_kind: 'invoice', p_doc_no: 'INV-TEST-0001', p_channel: 'email',
    p_doc_id: DOC.docId, p_customer_id: DOC.customerId,
    p_sent_to: 'ana.test@tests.invalid', p_pdf_path: uploadedPath(), p_status: 'sent',
    p_error: 'link fallback — no server-side sender',
  });
  assert.deepEqual(events, ['mail opened', 'log requested']);
  // B16 (AFTER-M3, Q6): it says what happened, never that a PDF was attached,
  // and hands back the mail link so the page can offer it again.
  assert.equal(res.reason, 'Your mail app should open with a link to the PDF; send it from there.');
  assert.doesNotMatch(res.reason, /attached/i);
  assert.equal(res.mailto, window.mailto);
  assert.ok(!requests.some(r => r.url.includes('/functions/v1/')), 'no email-sending service is called (Q6)');
});

test('two sends of one invoice are filed under two names, each linked to its own file', async () => {
  await sendViaWhatsAppLink(DOC);
  await sendViaWhatsAppLink(DOC);
  await settle();
  const paths = uploads().map(r => decodeURIComponent(r.url.slice(UPLOAD.length)));
  assert.equal(paths.length, 2);
  for (const p of paths) assert.match(p, PATH_SHAPE);
  assert.notEqual(paths[0], paths[1], 'the second send neither reuses nor replaces the first file');
  const signed = requests.filter(r => r.url.startsWith(SIGN)).map(r => decodeURIComponent(r.url.slice(SIGN.length)));
  assert.deepEqual(signed, paths, 'each link is signed for the file that send uploaded');
  assert.deepEqual(logRequests().map(r => JSON.parse(r.body).p_pdf_path), paths);
});

// ── B16: a window opened in the click (AFTER-11) ───────────────────────────────
test('a window opened in the click is sent to the chat once the link is ready, with its link back cut', async () => {
  const w = fakeWindow();
  const res = await sendViaWhatsAppLink(DOC, { win: w });
  await settle();
  assert.deepEqual(res, { ok: true });
  assert.match(w.sentTo, /^https:\/\/wa\.me\/\d+\?text=/);
  assert.equal(w.opener, null, 'the chat cannot reach back into this page');
  assert.equal(w.closed, false);
  const body = JSON.parse(logRequests()[0].body);
  assert.equal(body.p_status, 'sent');
  assert.equal(body.p_pdf_path, uploadedPath());
});

test('a window the browser blocked is said, logged as failed, and nothing is uploaded', async () => {
  const res = await sendViaWhatsAppLink(DOC, { win: null });
  await settle();
  assert.deepEqual(res, { ok: false, reason: WHATSAPP_BLOCKED });
  assert.equal(uploads().length, 0, 'no upload for a send that cannot open');
  const body = JSON.parse(logRequests()[0].body);
  assert.equal(body.p_status, 'failed');
  assert.equal(body.p_error, 'pop-up blocked');
  assert.ok(!events.includes('chat opened'));
});

test('without a window from the click (the Special page), a blocked window is not logged as sent', async () => {
  window.blockPopups = true;
  try {
    const res = await sendViaWhatsAppLink(DOC);
    await settle();
    assert.deepEqual(res, { ok: false, reason: WHATSAPP_BLOCKED });
    const body = JSON.parse(logRequests()[0].body);
    assert.equal(body.p_status, 'failed');
    assert.equal(body.p_error, 'pop-up blocked');
    assert.equal(body.p_pdf_path, uploadedPath(), 'the PDF was uploaded, so its path is kept');
  } finally { window.blockPopups = false; }
});

test('a failed upload closes the window opened for it', async () => {
  uploadReply = () => json(400, { statusCode: '400', error: 'Bad Request', message: 'upload refused (test)' });
  const w = fakeWindow();
  const res = await sendViaWhatsAppLink(DOC, { win: w });
  await settle();
  assert.equal(res.ok, false);
  assert.equal(w.closed, true);
  assert.equal(w.sentTo, null);
  assert.equal(JSON.parse(logRequests()[0].body).p_status, 'failed');
});

test('a window closed before the link was ready is not reported as sent', async () => {
  const w = fakeWindow(); w.closed = true;
  const res = await sendViaWhatsAppLink(DOC, { win: w });
  await settle();
  assert.equal(res.ok, false);
  assert.match(res.reason, /closed before the link was ready/);
  assert.equal(JSON.parse(logRequests()[0].body).p_error, 'window closed');
});

// ── B16: email from this device's mail app (AFTER-M3, Q6) ─────────────────────
/** A phone: it can share files. `share` is the test's. */
function withShareSheet(share, clipboard = async () => {}) {
  const before = Object.getOwnPropertyDescriptor(globalThis, 'navigator');
  Object.defineProperty(globalThis, 'navigator', { configurable: true, writable: true,
    value: { canShare: () => true, share, clipboard: { writeText: clipboard } } });
  return () => { if (before) Object.defineProperty(globalThis, 'navigator', before); else delete globalThis.navigator; };
}

test('a share sheet closed without choosing an app is "Not sent", logged as failed (cancelled)', async () => {
  const restore = withShareSheet(async () => { const e = new Error('closed'); e.name = 'AbortError'; throw e; });
  try {
    const res = await sendViaEmailAttachment(DOC);
    await settle();
    assert.deepEqual(res, { ok: false, reason: EMAIL_SHARE_CLOSED });
    const body = JSON.parse(logRequests()[0].body);
    assert.equal(body.p_channel, 'email');
    assert.equal(body.p_status, 'failed');
    assert.equal(body.p_error, 'cancelled');
    assert.equal(uploads().length, 0, 'nothing is uploaded for a shared file');
  } finally { restore(); }
});

test('the share sheet opens before anything else is awaited, and its result never says "attached"', async () => {
  let release; const clipboardDone = new Promise(r => { release = r; });
  const order = [];
  const restore = withShareSheet(async (data) => { order.push('share'); assert.equal(data.files.length, 1); },
    async () => { order.push('clipboard'); await clipboardDone; });
  try {
    const pending = sendViaEmailAttachment(DOC);
    await settle();
    assert.ok(order.includes('share'), 'the share started while the copy of the address was still pending');
    release();
    const res = await pending;
    assert.equal(res.ok, true);
    assert.equal(res.outcome, 'shared');
    assert.match(res.reason, /went to the app you chose/);
    assert.doesNotMatch(res.reason, /attached/i);
    await settle();
    assert.equal(JSON.parse(logRequests()[0].body).p_status, 'sent');
  } finally { restore(); }
});

test('a share the browser refuses for want of a tap asks for one, logs nothing, and works from that tap', async () => {
  let tries = 0;
  const restore = withShareSheet(async () => {
    tries++;
    if (tries === 1) { const e = new Error('needs a tap'); e.name = 'NotAllowedError'; throw e; }
  });
  try {
    const first = await sendViaEmailAttachment(DOC);
    await settle();
    assert.equal(first.ok, false);
    assert.equal(typeof first.shareAgain, 'function');
    assert.equal(logRequests().length, 0, 'nothing was shown, so nothing is logged');
    const again = await first.shareAgain();
    await settle();
    assert.equal(again.ok, true);
    assert.equal(again.outcome, 'shared');
    assert.equal(JSON.parse(logRequests()[0].body).p_status, 'sent');
  } finally { restore(); }
});

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
const { sendViaWhatsAppLink, sendViaEmailAttachment } =
  await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));

// ── fixture ────────────────────────────────────────────────────────────────
const DOC = {
  pdf: {}, kindLabel: 'Invoice', docNo: 'INV-TEST-0001', docKind: 'invoice',
  docId: '00000000-0000-4000-8000-000000000001', storeId: 'store-test',
  customerId: '00000000-0000-4000-8000-000000000002', customerName: 'Ana Test',
  phone: '+65 9123 4567', email: 'ana.test@tests.invalid',
};
const PATH = 'store-test/invoice/INV-TEST-0001.pdf';
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
  uploadReply = () => json(200, { Id: 'obj-test', Key: `invoice-pdfs/${PATH}` });
  globalThis.__fetch = async (input, init = {}) => {
    const url = String(input instanceof Request ? input.url : input);
    const body = typeof init.body === 'string' ? init.body : null;
    requests.push({ method: init.method ?? 'GET', url, body });
    if (url === RPC) { events.push('log requested'); return rpcReply(); }
    if (url.startsWith('https://db.invalid/storage/v1/object/sign/invoice-pdfs/')) {
      return json(200, { signedURL: `/object/sign/invoice-pdfs/${PATH}?token=t` }); }
    if (url.startsWith('https://db.invalid/storage/v1/object/invoice-pdfs/')) return uploadReply();
    return json(404, { message: `unexpected request ${url}` });
  };
  globalThis.window = {
    open: url => { events.push('chat opened'); window.opened = url; },
    location: { set href(v) { events.push('mail opened'); window.mailto = v; } },
  };
  console.warn = (...a) => warnings.push(a.map(String).join(' '));
  process.on('unhandledRejection', onUnhandled);
});
afterEach(() => {
  console.warn = consoleWarn;
  process.off('unhandledRejection', onUnhandled);
});

/** The client resolves the session before it fetches, so give it a few turns. */
async function settle() { for (let i = 0; i < 20; i++) await new Promise(r => setTimeout(r, 0)); }
const logRequests = () => requests.filter(r => r.url === RPC);

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
    p_sent_to: '6591234567', p_pdf_path: PATH, p_status: 'sent', p_error: null,
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
    p_sent_to: 'ana.test@tests.invalid', p_pdf_path: PATH, p_status: 'sent',
    p_error: 'link fallback — no server-side sender',
  });
  assert.deepEqual(events, ['mail opened', 'log requested']);
});

// A small harness for rendering the real pages in jsdom against a fake
// Supabase client (429: Users & Roles, Payment Methods, the password pages
// and the app shell). The pages are bundled from src with esbuild; only the
// Supabase client (and, when asked, the auth context) is replaced. Every name,
// email and phone used with it is made up.
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';
import { JSDOM, VirtualConsole } from 'jsdom';

export const REPO = fileURLToPath(new URL('../../', import.meta.url));

/** A jsdom window, with the globals React and the pages expect. */
export function setupDom(url = 'https://energia.invalid/') {
  // React reports an error a boundary caught through the window too; jsdom
  // would print each with the whole bundle in its stack. The boundaries'
  // own output is what the tests read.
  const virtualConsole = new VirtualConsole();
  if (typeof virtualConsole.forwardTo === 'function') virtualConsole.forwardTo(console, { jsdomErrors: 'none' });
  else virtualConsole.sendTo(console, { omitJSDOMErrors: true });
  const dom = new JSDOM('<!doctype html><html><body><div id="root"></div></body></html>', { url, pretendToBeVisual: true, virtualConsole });
  for (const k of ['window', 'document', 'navigator', 'HTMLElement', 'HTMLInputElement', 'HTMLSelectElement',
    'HTMLTextAreaElement', 'Element', 'Node', 'Event', 'KeyboardEvent', 'MouseEvent', 'getComputedStyle',
    'requestAnimationFrame', 'cancelAnimationFrame', 'MutationObserver', 'sessionStorage', 'localStorage', 'location', 'history']) {
    Object.defineProperty(globalThis, k, { value: dom.window[k], configurable: true, writable: true });
  }
  dom.window.confirm = () => true;
  dom.window.prompt = () => '';
  globalThis.IS_REACT_ACT_ENVIRONMENT = true;
  // Bundled as ESM, React's act() queues each task on a new MessageChannel and
  // never closes it; Node's ports then keep the runner alive after the last test.
  globalThis.MessageChannel = class {
    constructor() {
      const port = () => ({ onmessage: null, close() {} });
      this.port1 = port(); this.port2 = port();
      this.port1.postMessage = data => setImmediate(() => this.port2.onmessage?.({ data }));
      this.port2.postMessage = data => setImmediate(() => this.port1.onmessage?.({ data }));
    }
  };
  const consoleError = console.error;
  console.error = (...a) => {
    const s = String(a[0]);
    if (s.includes('not wrapped in act') || s.includes('Render error') || s.includes('The above error occurred')) return;
    consoleError(...a);
  };
  return dom;
}

/**
 * Bundle `contents` (an ES module that re-exports what a test needs) with the
 * Supabase client replaced by globalThis.__supabase and, with stubAuth, the
 * auth context by globalThis.__auth.
 */
export async function bundle(contents, { stubAuth = false } = {}) {
  const built = await build({
    stdin: { contents, loader: 'tsx', resolveDir: REPO },
    bundle: true, write: false, format: 'esm', jsx: 'automatic', platform: 'browser',
    loader: { '.css': 'empty' }, logLevel: 'silent',
    define: { 'process.env.NODE_ENV': '"development"', 'import.meta.env': '{"DEV":false,"VITE_SUPABASE_URL":"x","VITE_SUPABASE_ANON_KEY":"x"}' },
    plugins: [{ name: 'stubs', setup(b) {
      b.onResolve({ filter: /(^|\/)lib\/supabase$|^\.\/supabase$/ }, () => ({ path: 'supabase', namespace: 'stub' }));
      b.onLoad({ filter: /^supabase$/, namespace: 'stub' }, () => ({ loader: 'js',
        contents: 'export const supabase = new Proxy({}, { get: (_, k) => globalThis.__supabase[k] });' }));
      if (stubAuth) {
        b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: 'auth', namespace: 'stub' }));
        b.onLoad({ filter: /^auth$/, namespace: 'stub' }, () => ({ loader: 'js',
          contents: 'export const useAuth = () => globalThis.__auth; export const AuthProvider = ({ children }) => children;' }));
      }
    } }],
  });
  return await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
}

/**
 * A fake Supabase client. `tables[name]` holds rows; `rpc[name](args)` and
 * `invoke[name](body)` answer calls; `fail[name]` makes a table or rpc fail.
 * Every call is recorded in `calls`.
 */
export function fakeSupabase({ tables = {}, rpc = {}, invoke = {}, fail = {}, gate = {}, auth } = {}) {
  const calls = [];
  // gate[table]: a promise a read of that table waits for (a slow network).
  const client = { calls, tables, rpcHandlers: rpc, invokeHandlers: invoke, fail, gate };
  class Query {
    constructor(table) { Object.assign(this, { table, op: 'select', filters: [], payload: null, returning: false, single: false }); }
    select() { if (this.op !== 'select') this.returning = true; return this; }
    insert(p) { this.op = 'insert'; this.payload = p; return this; }
    update(p) { this.op = 'update'; this.payload = p; return this; }
    delete() { this.op = 'delete'; return this; }
    eq(c, v) { this.filters.push({ c, v }); return this; }
    is(c, v) { this.filters.push({ c, v }); return this; }
    in() { return this; }
    order() { return this; }
    limit() { return this; }
    maybeSingle() { this.single = true; return this; }
    async exec() {
      calls.push({ table: this.table, op: this.op, payload: this.payload, filters: this.filters });
      await Promise.resolve();
      if (gate[this.table]) await gate[this.table];
      if (fail[this.table]) return { data: null, error: { message: fail[this.table] } };
      const rows = (tables[this.table] ?? []);
      const match = r => this.filters.every(f => (r[f.c] ?? null) === f.v);
      if (this.op === 'select') {
        const found = rows.filter(match);
        return { data: structuredClone(this.single ? found[0] ?? null : found), error: null };
      }
      if (this.op === 'insert') {
        const row = { id: `new-${rows.length + 1}`, deleted_at: null, is_active: true, ...this.payload };
        rows.push(row); tables[this.table] = rows;
        return { data: this.returning ? [structuredClone(row)] : null, error: null };
      }
      if (this.op === 'update') {
        const hit = rows.filter(match);
        for (const r of hit) Object.assign(r, this.payload);
        return { data: this.returning ? structuredClone(hit) : null, error: null };
      }
      return { data: null, error: null };
    }
    then(res, rej) { return this.exec().then(res, rej); }
  }
  client.from = table => new Query(table);
  client.rpc = async (name, args) => {
    calls.push({ rpc: name, args });
    await Promise.resolve();
    if (fail[name]) return { data: null, error: { message: fail[name] } };
    const fn = rpc[name];
    if (!fn) return { data: null, error: { message: `unknown rpc ${name}` } };
    return { data: structuredClone(fn(args)), error: null };
  };
  client.functions = {
    invoke: async (name, opts) => {
      calls.push({ fn: name, body: opts?.body });
      await Promise.resolve();
      const fn = invoke[name];
      return fn ? fn(opts?.body) : { data: {}, error: null };
    },
  };
  const listeners = [];
  client.listeners = listeners;
  client.auth = auth ?? {
    session: null,
    getSession: async () => ({ data: { session: client.auth.session } }),
    onAuthStateChange: cb => { listeners.push(cb); return { data: { subscription: { unsubscribe() {} } } }; },
    signOut: async () => { calls.push({ auth: 'signOut' }); client.auth.session = null; listeners.forEach(l => l('SIGNED_OUT', null)); return {}; },
    refreshSession: async () => ({ data: {} }),
    signInWithPassword: async () => ({ error: null }),
  };
  /** Tell every auth listener about an event, as supabase-js would. */
  client.emit = (event, session) => { client.auth.session = session; listeners.forEach(l => l(event, session)); };
  return client;
}

/** A made-up access token carrying these claims (not signed; the pages only read it). */
export function tokenWith(claims) {
  const b64 = v => Buffer.from(JSON.stringify(v)).toString('base64url');
  return `${b64({ alg: 'ES256' })}.${b64(claims)}.signature`;
}

/** Helpers bound to one bundle's React (act, createRoot) and its window. */
export function driver({ React, act, createRoot }, dom) {
  let root = null;
  const tick = async (n = 8) => { for (let i = 0; i < n; i++) await act(async () => { await new Promise(r => setTimeout(r, 0)); }); };
  return {
    tick,
    async mount(element) {
      if (root) await act(async () => root.unmount());
      document.body.innerHTML = '<div id="root"></div>';
      root = createRoot(document.getElementById('root'));
      await act(async () => root.render(element));
      await tick();
    },
    async unmount() { if (root) await act(async () => root.unmount()); root = null; },
    text: () => document.body.textContent,
    button: (label, scope = document) => [...scope.querySelectorAll('button')]
      .find(b => b.textContent.trim() === label || b.getAttribute('aria-label') === label),
    async click(el) {
      assert.ok(el, 'the element to click exists');
      await act(async () => { el.dispatchEvent(new dom.window.MouseEvent('click', { bubbles: true })); });
      await tick();
    },
    async setValue(el, value) {
      assert.ok(el, 'the field exists');
      const proto = el.tagName === 'SELECT' ? dom.window.HTMLSelectElement.prototype
        : el.tagName === 'TEXTAREA' ? dom.window.HTMLTextAreaElement.prototype : dom.window.HTMLInputElement.prototype;
      await act(async () => {
        Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
        el.dispatchEvent(new dom.window.Event(el.tagName === 'SELECT' ? 'change' : 'input', { bubbles: true }));
      });
      await tick(2);
    },
    async toggle(el) {
      assert.ok(el, 'the box exists');
      await act(async () => { el.click(); });
      await tick(2);
    },
    async submit(form) {
      await act(async () => { form.dispatchEvent(new dom.window.Event('submit', { bubbles: true, cancelable: true })); });
      await tick();
    },
    /** The field a label names, by its htmlFor. */
    labelled(text) {
      const label = [...document.querySelectorAll('label')].find(l => l.textContent.trim().startsWith(text));
      if (!label) return null;
      const id = label.getAttribute('for');
      return id ? document.getElementById(id) : null;
    },
  };
}

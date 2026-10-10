// The shared window (src/components/ui.tsx): only the window on top answers
// Escape, and ReasonModal can check a shortest reason and stay open until its
// save works.
//
// The real components are bundled and mounted in jsdom. The case that
// prompted the first part (SALES-EXTRAS-M5): Confirm Exchange opens over the
// exchange being entered, which asks before it discards. Every open window
// listened for Escape on the document, so one Escape closed Confirm Exchange
// and also asked to throw away the whole exchange below it. The second part
// (EVENTS-11): a one-letter reason for dismissing a staff-link registration
// closed the window and then showed the server's refusal at the top of the
// tab, so the manager started again.
//
// Two cases came from the review of 9 Oct. A window whose top window belongs
// to a part of the page inside it, when the page draws again while both are
// open: the window below then listens after the one on top, and a browser
// finishes closing the top window between the two listeners, so the window
// below found itself on top and asked to discard its form. And the dev build
// (StrictMode mounts a window twice) left a reason window on 'Saving…'.
//
// Run: node --test scripts/ui/tests/modal-escape.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const built = await build({
  stdin: {
    contents: `
      import React from 'react';
      import { createRoot } from 'react-dom/client';
      import { act } from 'react';
      import { flushSync } from 'react-dom';
      import { Modal, ReasonModal } from './src/components/ui';

      // Two windows: the one below holds a form (it asks before discarding);
      // the one on top opens later. 'nested' puts the top one inside the
      // lower one's body; 'before' renders it earlier in the page than the
      // lower one, though it opened later, so the lower one is drawn on top.
      function Stack({ layout, log }) {
        const [lower, setLower] = React.useState(true);
        const [upper, setUpper] = React.useState(true);
        const top = upper && React.createElement(Modal, { title: 'Upper', onClose: () => { log.push('upper closed'); setUpper(false); } },
          React.createElement('p', null, 'Upper body'));
        const low = lower && React.createElement(Modal, { title: 'Lower', confirmClose: true,
            onClose: () => { log.push('lower closed'); setLower(false); } },
          React.createElement('p', null, 'Lower body'), layout === 'nested' ? top : null);
        return React.createElement('div', null,
          layout === 'before' ? top : null, low, layout === 'after' ? top : null);
      }

      function Reason({ log, answers, minLength }) {
        const [open, setOpen] = React.useState(true);
        return open ? React.createElement(ReasonModal, {
          title: 'Dismiss', label: 'Why?', confirmLabel: 'Dismiss', minLength,
          onClose: () => { log.push('closed'); setOpen(false); },
          onSubmitAsync: async reason => { log.push('sent ' + reason); return answers.shift() ?? null; },
        }) : React.createElement('p', { id: 'gone' }, 'closed');
      }

      // The window on top belongs to a part of the page inside the window
      // below, and opens later, as a click opens it. While it is open the page
      // draws again (a refetch, a timer): the window below gets a new onClose,
      // so it listens again, now after the one on top. The top window closes
      // at once (flushSync), as a browser finishes a click's update between
      // two listeners of one key.
      function Owned({ log, api }) {
        const [, setTick] = React.useState(0);
        const [lower, setLower] = React.useState(true);
        api.redraw = () => setTick(t => t + 1);
        return lower ? React.createElement(Modal, { title: 'Lower', confirmClose: true,
            onClose: () => { log.push('lower closed'); setLower(false); } },
          React.createElement(Child, { log, api })) : null;
      }
      function Child({ log, api }) {
        const [upper, setUpper] = React.useState(false);
        api.openUpper = () => setUpper(true);
        return React.createElement('div', null, React.createElement('p', null, 'Lower body'),
          upper && React.createElement(Modal, { title: 'Upper',
              onClose: () => { log.push('upper closed'); flushSync(() => setUpper(false)); } },
            React.createElement('p', null, 'Upper body')));
      }

      function Plain({ log }) {
        return React.createElement(ReasonModal, {
          title: 'Delete', label: 'Why?', onClose: () => log.push('closed'), onSubmit: r => log.push('submitted ' + r),
        });
      }

      window.__act = act;
      window.__mount = (what, props, strict) => {
        const root = createRoot(document.getElementById('root'));
        const C = { stack: Stack, reason: Reason, owned: Owned, plain: Plain }[what];
        const el = React.createElement(C, props);
        // StrictMode, as src/main.tsx renders the app: in development each
        // window is mounted, unmounted and mounted again.
        return act(async () => { root.render(strict ? React.createElement(React.StrictMode, null, el) : el); });
      };
    `,
    resolveDir: process.cwd(), loader: 'ts',
  },
  bundle: true, write: false, format: 'iife', jsx: 'automatic',
  loader: { '.css': 'empty' },
  define: { 'process.env.NODE_ENV': '"development"' },
  // ui.tsx reads the signed-in role (RoleGate) through AuthContext, which
  // pulls in the Supabase client; neither is used by the windows.
  plugins: [{
    name: 'stub-auth',
    setup(b) {
      b.onResolve({ filter: /(^|\/)context\/AuthContext$/ }, () => ({ path: 'auth-stub', namespace: 'stub' }));
      b.onLoad({ filter: /.*/, namespace: 'stub' }, () => ({
        contents: 'export const useAuth = () => ({ profile: null });', loader: 'js',
      }));
    },
  }],
});
const bundle = built.outputFiles[0].text;

async function mount(what, props, { strict = false } = {}) {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', { runScripts: 'dangerously', pretendToBeVisual: true });
  const { window } = dom;
  window.IS_REACT_ACT_ENVIRONMENT = true;
  // React's act() queues work on a MessageChannel, which jsdom does not have.
  window.MessageChannel = class {
    constructor() {
      const port = () => ({ onmessage: null, close() {} });
      this.port1 = port(); this.port2 = port();
      this.port1.postMessage = data => setImmediate(() => this.port2.onmessage?.({ data }));
      this.port2.postMessage = data => setImmediate(() => this.port1.onmessage?.({ data }));
    }
  };
  const confirms = [];
  window.confirm = msg => { confirms.push(msg); return false; };
  const script = window.document.createElement('script');
  script.textContent = bundle;
  window.document.body.appendChild(script);
  await window.__mount(what, props, strict);
  const act = fn => window.__act(async () => { await fn(); });
  // Cancelable, as a key pressed in a browser is.
  const escape = () => act(() => {
    window.document.dispatchEvent(new window.KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
  });
  const titles = () => [...window.document.querySelectorAll('.modal h3')].map(h => h.textContent);
  return { window, document: window.document, confirms, act, escape, titles };
}

for (const layout of ['after', 'nested']) {
  test(`Escape closes only the window on top, and never asks about the one below (${layout})`, async () => {
    const log = [];
    const page = await mount('stack', { layout, log });
    assert.deepEqual(page.titles(), ['Lower', 'Upper']);
    await page.escape();
    assert.deepEqual(log, ['upper closed'], 'only the upper window closed');
    assert.deepEqual(page.confirms, [], 'and the one below did not ask to discard');
    assert.deepEqual(page.titles(), ['Lower']);
    // Now the form is on top: Escape asks before discarding it, and No keeps it.
    await page.escape();
    assert.deepEqual(page.confirms, ['Discard what you have entered? It will not be saved.']);
    assert.deepEqual(log, ['upper closed'], 'answering No keeps the form');
    assert.deepEqual(page.titles(), ['Lower']);
    page.window.close();
  });
}

test('Escape closes only the window on top when the page draws again while it is open', async () => {
  const log = [];
  const api = {};
  const page = await mount('owned', { log, api });
  assert.deepEqual(page.titles(), ['Lower']);
  await page.act(() => api.openUpper());
  assert.deepEqual(page.titles(), ['Lower', 'Upper']);
  // The page draws again: the window below now listens after the one on top.
  await page.act(() => api.redraw());
  assert.deepEqual(page.titles(), ['Lower', 'Upper']);
  await page.escape();
  assert.deepEqual(log, ['upper closed'], 'only the upper window closed');
  assert.deepEqual(page.confirms, [], 'and the one below did not ask to discard');
  assert.deepEqual(page.titles(), ['Lower']);
  // The next Escape is for the form, which asks first; No keeps it.
  await page.escape();
  assert.deepEqual(page.confirms, ['Discard what you have entered? It will not be saved.']);
  assert.deepEqual(log, ['upper closed']);
  page.window.close();
});

test('the window drawn on top is the one that answers, whichever opened first', async () => {
  const log = [];
  const page = await mount('stack', { layout: 'before', log });
  // Same z-index: the later one in the page is drawn over the earlier one.
  assert.deepEqual(page.titles(), ['Upper', 'Lower']);
  await page.escape();
  assert.deepEqual(log, [], 'the form on top asked first, and No kept everything');
  assert.equal(page.confirms.length, 1);
  page.window.close();
});

test('ReasonModal: a reason shorter than minLength is caught before anything is sent', async () => {
  const log = [];
  const page = await mount('reason', { log, answers: [], minLength: 3 });
  const { document } = page;
  assert.ok(document.querySelector('.modal').textContent.includes('At least 3 characters.'), 'the rule is shown');
  const area = document.querySelector('textarea');
  const type = value => page.act(() => {
    Object.getOwnPropertyDescriptor(page.window.HTMLTextAreaElement.prototype, 'value').set.call(area, value);
    area.dispatchEvent(new page.window.Event('input', { bubbles: true }));
  });
  const confirmButton = () => [...document.querySelectorAll('.modal-footer button')].find(b => b.textContent === 'Dismiss');
  await type('ok');
  await page.act(() => confirmButton().click());
  assert.equal(document.querySelector('[role="alert"]').textContent, 'Give at least 3 characters.');
  assert.deepEqual(log, [], 'nothing was sent');
  await type('  ok ');
  await page.act(() => confirmButton().click());
  assert.deepEqual(log, [], 'spaces do not count');
  page.window.close();
});

test('ReasonModal: the window stays open, showing the refusal, until the save works', async () => {
  const log = [];
  const page = await mount('reason', { log, answers: ['Only a recorded or waiting registration can be dismissed'], minLength: 3 });
  const { document } = page;
  const area = document.querySelector('textarea');
  await page.act(() => {
    Object.getOwnPropertyDescriptor(page.window.HTMLTextAreaElement.prototype, 'value').set.call(area, ' A test ');
    area.dispatchEvent(new page.window.Event('input', { bubbles: true }));
  });
  const confirmButton = () => [...document.querySelectorAll('.modal-footer button')].find(b => /Dismiss|Saving/.test(b.textContent));
  await page.act(() => confirmButton().click());
  await page.act(() => new Promise(r => setTimeout(r, 0)));
  assert.deepEqual(log, ['sent A test'], 'the reason was sent, trimmed');
  assert.ok(document.querySelector('.modal'), 'the window is still open');
  assert.equal(document.querySelector('[role="alert"]').textContent, 'Only a recorded or waiting registration can be dismissed');
  assert.equal(document.querySelector('textarea').value, ' A test ', 'what was typed is kept');
  await page.act(() => confirmButton().click());
  await page.act(() => new Promise(r => setTimeout(r, 0)));
  assert.deepEqual(log, ['sent A test', 'sent A test', 'closed'], 'saved the second time, then closed');
  assert.ok(document.getElementById('gone'));
  page.window.close();
});

test('ReasonModal in the dev build (StrictMode): a refusal shows, and the next save closes the window', async () => {
  const log = [];
  const page = await mount('reason', { log, answers: ['Refused for a test'], minLength: 3 }, { strict: true });
  const { document } = page;
  const area = document.querySelector('textarea');
  await page.act(() => {
    Object.getOwnPropertyDescriptor(page.window.HTMLTextAreaElement.prototype, 'value').set.call(area, 'A test');
    area.dispatchEvent(new page.window.Event('input', { bubbles: true }));
  });
  const confirmButton = () => [...document.querySelectorAll('.modal-footer button')].find(b => /Dismiss|Saving/.test(b.textContent));
  await page.act(() => confirmButton().click());
  await page.act(() => new Promise(r => setTimeout(r, 0)));
  assert.deepEqual(log, ['sent A test']);
  assert.equal(document.querySelector('[role="alert"]')?.textContent, 'Refused for a test', 'the refusal shows');
  assert.equal(confirmButton().textContent, 'Dismiss', 'the button is not left on Saving…');
  assert.equal(confirmButton().disabled, false, 'and it can be pressed again');
  await page.act(() => confirmButton().click());
  await page.act(() => new Promise(r => setTimeout(r, 0)));
  assert.deepEqual(log, ['sent A test', 'sent A test', 'closed'], 'saved the second time, then closed');
  assert.ok(document.getElementById('gone'));
  page.window.close();
});

test('ReasonModal without the new options works as before', async () => {
  const log = [];
  const page = await mount('plain', { log });
  const { document } = page;
  const confirmButton = () => [...document.querySelectorAll('.modal-footer button')].find(b => b.textContent === 'Confirm');
  await page.act(() => confirmButton().click());
  assert.equal(document.querySelector('[role="alert"]').textContent, 'This field is required.');
  assert.ok(!document.querySelector('.modal').textContent.includes('characters'), 'no length rule is shown');
  const area = document.querySelector('textarea');
  await page.act(() => {
    Object.getOwnPropertyDescriptor(page.window.HTMLTextAreaElement.prototype, 'value').set.call(area, 'x');
    area.dispatchEvent(new page.window.Event('input', { bubbles: true }));
  });
  await page.act(() => confirmButton().click());
  assert.deepEqual(log, ['submitted x'], 'one letter is enough, and the caller closes the window');
  page.window.close();
});

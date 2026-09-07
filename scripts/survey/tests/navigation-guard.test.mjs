// useNavigationGuard: sentinel history entry + popstate interception + cleanup.
// Run: node --test scripts/survey/tests/navigation-guard.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';
import React, { act } from 'react';
import { createRoot } from 'react-dom/client';

const require = createRequire(import.meta.url);
const dir = await mkdtemp(join(tmpdir(), 'energia-survey-guard-'));
await build({
  entryPoints: ['src/hooks/useNavigationGuard.ts'],
  outfile: join(dir, 'guard.mjs'),
  bundle: true, format: 'esm', platform: 'node',
  plugins: [{
    name: 'shared-react',
    setup(b) {
      b.onResolve({ filter: /^react(?:\/.*)?$/ }, a => ({ path: require.resolve(a.path), external: true }));
    },
  }],
});
const { useNavigationGuard } = await import(pathToFileURL(join(dir, 'guard.mjs')).href);

const dom = new JSDOM('<!doctype html><html><body></body></html>', { url: 'https://example.test/survey/tok' });
globalThis.window = dom.window;
globalThis.document = dom.window.document;
globalThis.IS_REACT_ACT_ENVIRONMENT = true;

function mount(getWhen) {
  const node = document.createElement('div');
  document.body.appendChild(node);
  const root = createRoot(node);
  const calls = { blocked: 0 };
  let api;
  function Harness({ when }) {
    api = useNavigationGuard({ when, onBlockedPop: () => { calls.blocked++; } });
    return null;
  }
  const render = when => act(() => root.render(React.createElement(Harness, { when })));
  render(getWhen());
  return {
    calls,
    get api() { return api; },
    setWhen: render,
    pop() { act(() => dom.window.dispatchEvent(new dom.window.PopStateEvent('popstate', { state: dom.window.history.state }))); },
    beforeUnloadPrevented() {
      const e = new dom.window.Event('beforeunload', { cancelable: true });
      dom.window.dispatchEvent(e);
      return e.defaultPrevented;
    },
    close() { act(() => root.unmount()); node.remove(); },
  };
}

test('clean form: no sentinel, no beforeunload prompt', () => {
  const ui = mount(() => false);
  try {
    assert.equal(dom.window.history.state?.__surveyGuard, undefined);
    assert.equal(ui.beforeUnloadPrevented(), false);
  } finally { ui.close(); }
});

test('dirty form: arms a single sentinel and the beforeunload prompt', () => {
  const before = dom.window.history.length;
  const ui = mount(() => true);
  try {
    assert.equal(dom.window.history.state?.__surveyGuard, true);
    assert.equal(dom.window.history.length, before + 1, 'exactly one history entry added');
    assert.equal(ui.beforeUnloadPrevented(), true);
  } finally { ui.close(); }
});

test('dirty form: Back is intercepted (dialog asked, customer stays)', () => {
  const ui = mount(() => true);
  try {
    ui.pop();
    assert.equal(ui.calls.blocked, 1);
    assert.equal(dom.window.history.state?.__surveyGuard, true, 're-armed so the next Back is caught too');
    ui.pop();
    assert.equal(ui.calls.blocked, 2);
  } finally { ui.close(); }
});

test('clean form: Back is not intercepted', () => {
  const ui = mount(() => false);
  try {
    ui.pop();
    assert.equal(ui.calls.blocked, 0);
  } finally { ui.close(); }
});

test('becoming clean again removes the beforeunload prompt', () => {
  const ui = mount(() => true);
  try {
    assert.equal(ui.beforeUnloadPrevented(), true);
    ui.setWhen(false);
    assert.equal(ui.beforeUnloadPrevented(), false);
  } finally { ui.close(); }
});

test('confirmLeave performs a real navigation and stops intercepting', () => {
  const ui = mount(() => true);
  try {
    let went = null;
    const realGo = dom.window.history.go.bind(dom.window.history);
    dom.window.history.go = (n) => { went = n; };
    dom.window.history.back = () => { went = -1; };
    act(() => ui.api.confirmLeave());
    assert.ok(went === -2 || went === -1, 'navigated backwards past the sentinel');
    dom.window.history.go = realGo;
  } finally { ui.close(); }
});

test('unmount removes listeners', () => {
  const ui = mount(() => true);
  ui.close();
  const e = new dom.window.Event('beforeunload', { cancelable: true });
  dom.window.dispatchEvent(e);
  assert.equal(e.defaultPrevented, false);
});

test.after(async () => { dom.window.close(); await rm(dir, { recursive: true, force: true }); });

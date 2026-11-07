// A popup closes on a click on its backdrop, and not on a drag that only starts
// or ends there (screen recording of 7 Nov 2026: selecting text in a field and
// letting go outside the popup closed it).
//
// The real shared window is mounted in jsdom and given the events a browser
// sends. jsdom does not work out the click of a drag by itself, so the tests send
// it where a browser does: to the nearest element holding both ends, the backdrop.
// popup-drag-outside-browser.mjs makes the same drags with a real mouse in Chrome,
// on every popup. Every name is made up.
//
// Run: node --test scripts/ui/tests/popup-drag-outside.test.mjs
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { setupDom, bundle, driver, REPO } from '../page-harness.mjs';

const dom = setupDom();
const mod = await bundle(`
  import React from 'react';
  export { Modal } from './src/components/ui';
  export { createRoot } from 'react-dom/client';
  export { act } from 'react';
  export { React };
`, { stubAuth: true });
const { Modal, React, act } = mod;
const d = driver(mod, dom);
after(async () => { await d.unmount(); dom.window.close(); });

const fire = (el, type) => act(async () => { el.dispatchEvent(new dom.window.MouseEvent(type, { bubbles: true, cancelable: true })); });
const gesture = async (pressOn, releaseOn, clickOn) => {
  await fire(pressOn, 'mousedown');
  await fire(releaseOn, 'mouseup');
  if (clickOn) await fire(clickOn, 'click');
};

let asked, closed, answer;
dom.window.confirm = msg => { asked.push(msg); return answer; };

/** Opens one window with a field, as a form does. */
async function open(props = {}, children = React.createElement('input', { defaultValue: 'Some made-up text' })) {
  asked = []; closed = []; answer = false;
  function Page() {
    const [shown, setShown] = React.useState(true);
    return shown ? React.createElement(Modal, { title: 'Made up', ...props, onClose: () => { closed.push('window'); setShown(false); } }, children) : null;
  }
  await d.mount(React.createElement(Page));
  return { backdrop: document.querySelector('.modal-overlay'), field: document.querySelector('.modal input') };
}

test('selecting text and letting go on the backdrop leaves the window open', async () => {
  const { backdrop, field } = await open();
  await gesture(field, backdrop, backdrop);
  assert.deepEqual(closed, []);
  assert.ok(document.querySelector('.modal'));
});

test('on a form it does not ask to discard either', async () => {
  const { backdrop, field } = await open({ confirmClose: true });
  await gesture(field, backdrop, backdrop);
  assert.deepEqual(asked, [], 'nothing was asked');
  assert.deepEqual(closed, []);
});

test('a drag from the backdrop into the window leaves it open', async () => {
  const { backdrop, field } = await open({ confirmClose: true });
  await gesture(backdrop, field, backdrop);
  assert.deepEqual(asked, []);
  assert.deepEqual(closed, []);
});

test('a click on the backdrop still closes the window', async () => {
  const { backdrop } = await open();
  await gesture(backdrop, backdrop, backdrop);
  assert.deepEqual(closed, ['window']);
});

test('a click on the backdrop still asks first on a form, and No keeps it', async () => {
  const { backdrop } = await open({ confirmClose: true });
  await gesture(backdrop, backdrop, backdrop);
  assert.equal(asked.length, 1);
  assert.match(asked[0], /^Discard what you have entered\?/);
  assert.deepEqual(closed, [], 'answering No keeps the form');
  answer = true;
  await gesture(backdrop, backdrop, backdrop);
  assert.equal(asked.length, 2);
  assert.deepEqual(closed, ['window'], 'answering Yes closes it');
});

test('a real click right after a drag closes it: the drag is not remembered', async () => {
  const { backdrop, field } = await open();
  await gesture(field, backdrop, backdrop);
  assert.deepEqual(closed, []);
  await gesture(backdrop, backdrop, backdrop);
  assert.deepEqual(closed, ['window']);
});

test('a drag that ends off the page sends no click, and the next real click still closes it', async () => {
  const { backdrop, field } = await open();
  await fire(field, 'mousedown');
  assert.deepEqual(closed, []);
  await gesture(backdrop, backdrop, backdrop);
  assert.deepEqual(closed, ['window']);
});

test('a click with no press before it closes it, as assistive technology may send', async () => {
  const { backdrop } = await open();
  await fire(backdrop, 'click');
  assert.deepEqual(closed, ['window']);
});

test('a control in the window that stops its mouse events is still seen', async () => {
  const stop = e => e.stopPropagation();
  const { backdrop, field } = await open({}, React.createElement('input', { onMouseDown: stop, onMouseUp: stop, onClick: stop }));
  await gesture(field, backdrop, backdrop);
  assert.deepEqual(closed, []);
});

test('a click inside the window does nothing', async () => {
  const { field } = await open();
  await gesture(field, field, field);
  assert.deepEqual(closed, []);
});

test('with one window over another, a drag closes neither and a click only the top one', async () => {
  asked = []; closed = []; answer = false;
  function Page() {
    const [upper, setUpper] = React.useState(true);
    return React.createElement(Modal, { title: 'Below', confirmClose: true, onClose: () => closed.push('below') },
      upper && React.createElement(Modal, { title: 'On top', onClose: () => { closed.push('top'); setUpper(false); } },
        React.createElement('input', { defaultValue: 'Some made-up text' })));
  }
  await d.mount(React.createElement(Page));
  const overlays = document.querySelectorAll('.modal-overlay');
  assert.equal(overlays.length, 2);
  const top = overlays[1];
  await gesture(top.querySelector('input'), top, top);
  assert.deepEqual(closed, []);
  assert.deepEqual(asked, []);
  await gesture(top, top, top);
  assert.deepEqual(closed, ['top']);
  assert.deepEqual(asked, [], 'the form below was not asked about');
});

test('no popup goes back to closing on the bare click check, which a drag also passes', () => {
  const tsx = dir => readdirSync(dir, { withFileTypes: true }).flatMap(e =>
    e.isDirectory() ? tsx(join(dir, e.name)) : e.name.endsWith('.tsx') ? [join(dir, e.name)] : []);
  const bare = /onClick=\{[^}]*(\.target === \w+\.currentTarget|\.currentTarget === \w+\.target)/;
  const found = tsx(join(REPO, 'src')).filter(f => bare.test(readFileSync(f, 'utf8')));
  assert.deepEqual(found, [], 'use useBackdropClose for a backdrop');
});

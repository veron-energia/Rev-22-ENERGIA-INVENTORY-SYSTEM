// The show/hide control on a password field.
//
// The real component is bundled and mounted in jsdom, so these assert what it
// actually renders rather than a description of it.
import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
import { JSDOM } from 'jsdom';

const built = await build({
  stdin: {
    contents: `
      import React from 'react';
      import { createRoot } from 'react-dom/client';
      import { PasswordInput } from './src/components/PasswordInput';

      function Form() {
        const [pw, setPw] = React.useState('');
        const [confirm, setConfirm] = React.useState('');
        const [submitted, setSubmitted] = React.useState(0);
        return React.createElement('form', { onSubmit: e => { e.preventDefault(); setSubmitted(n => n + 1); } },
          React.createElement(PasswordInput, { id: 'pw', value: pw,
            onChange: e => setPw(e.target.value), autoComplete: 'new-password' }),
          React.createElement(PasswordInput, { id: 'confirm', value: confirm,
            onChange: e => setConfirm(e.target.value), autoComplete: 'new-password' }),
          React.createElement('output', { id: 'submits' }, String(submitted)));
      }
      window.__mount = () => createRoot(document.getElementById('root')).render(React.createElement(Form));
    `,
    resolveDir: process.cwd(), loader: 'ts',
  },
  bundle: true, write: false, format: 'iife', jsx: 'automatic',
  loader: { '.css': 'empty' },
});
const bundle = built.outputFiles[0].text;

function mount() {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {
    runScripts: 'dangerously', pretendToBeVisual: true,
  });
  const { window } = dom;
  const script = window.document.createElement('script');
  script.textContent = bundle;
  window.document.body.appendChild(script);
  window.__mount();
  return window;
}
const settle = () => new Promise(r => setTimeout(r, 40));

test('both fields start hidden', async () => {
  const w = mount(); await settle();
  const inputs = [...w.document.querySelectorAll('input')];
  assert.equal(inputs.length, 2);
  assert.deepEqual(inputs.map(i => i.type), ['password', 'password'],
    'a freshly opened form must not reveal a password');
});

test('each field has its own toggle, and one does not reveal the other', async () => {
  const w = mount(); await settle();
  const buttons = [...w.document.querySelectorAll('button')];
  assert.equal(buttons.length, 2, 'a password and its confirmation are two decisions');
  buttons[0].click(); await settle();
  assert.deepEqual([...w.document.querySelectorAll('input')].map(i => i.type),
    ['text', 'password'], 'revealing one revealed the other');
});

test('the toggle is a button, not a submit', async () => {
  const w = mount(); await settle();
  const btn = w.document.querySelector('button');
  assert.equal(btn.getAttribute('type'), 'button');
  btn.click(); await settle();
  assert.equal(w.document.querySelector('#submits').textContent, '0',
    'toggling visibility submitted the form');
});

test('the value survives toggling', async () => {
  const w = mount(); await settle();
  const input = w.document.querySelector('input');
  Object.getOwnPropertyDescriptor(w.HTMLInputElement.prototype, 'value').set.call(input, 'hunter2');
  input.dispatchEvent(new w.Event('input', { bubbles: true }));
  await settle();
  w.document.querySelector('button').click(); await settle();
  assert.equal(w.document.querySelector('input').value, 'hunter2');
});

test('the accessible label says what the button will do', async () => {
  const w = mount(); await settle();
  let btn = w.document.querySelector('button');
  assert.equal(btn.getAttribute('aria-label'), 'Show password');
  assert.equal(btn.getAttribute('aria-pressed'), 'false');
  btn.click(); await settle();
  btn = w.document.querySelector('button');
  assert.equal(btn.getAttribute('aria-label'), 'Hide password');
  assert.equal(btn.getAttribute('aria-pressed'), 'true');
});

test('autocomplete is passed through untouched', async () => {
  const w = mount(); await settle();
  assert.deepEqual([...w.document.querySelectorAll('input')].map(i => i.getAttribute('autocomplete')),
    ['new-password', 'new-password'],
    'password managers rely on this, so the wrapper must not swallow it');
});

test('the toggle is reachable from the keyboard', async () => {
  const w = mount(); await settle();
  const btn = w.document.querySelector('button');
  assert.notEqual(btn.tabIndex, -1, 'the control must be tabbable');
});

test('visibility is not remembered between mounts', async () => {
  const a = mount(); await settle();
  a.document.querySelector('button').click(); await settle();
  assert.equal(a.document.querySelector('input').type, 'text');
  const b = mount(); await settle();
  assert.equal(b.document.querySelector('input').type, 'password',
    'a newly opened form must start hidden');
});

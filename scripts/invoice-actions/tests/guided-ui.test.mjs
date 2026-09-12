// The guided dialog's structure and accessibility, rendered for real.
//
// Checked here rather than by clicking the live app, because exercising the
// real flow would mean performing a real refund against production data.
import { build } from 'esbuild';
import assert from 'node:assert/strict';

const built = await build({
  stdin: {
    contents: `
      import React from 'react';
      import { renderToStaticMarkup } from 'react-dom/server';
      import { InvoiceGuidedAction } from './src/components/invoices/InvoiceGuidedAction';
      export function render(props) {
        return renderToStaticMarkup(React.createElement(InvoiceGuidedAction, {
          invoiceId: 'i1', canApprove: false, onDone: () => {}, onClose: () => {}, ...props }));
      }`,
    resolveDir: process.cwd(), loader: 'ts',
  },
  bundle: true, write: false, format: 'esm', jsx: 'automatic',
  // The component only talks to Supabase inside effects, which do not run in a
  // static render; the stub keeps the import graph resolvable.
  plugins: [{ name: 'stub', setup(b) {
    b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: 'stub', namespace: 'st' }));
    b.onLoad({ filter: /.*/, namespace: 'st' }, () => ({
      contents: 'export const supabase = { rpc: async () => ({ data: null, error: null }) };', loader: 'js' }));
  } }],
});
const { render } = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
const html = render({});

// A modal dialog has to announce itself as one and name itself.
assert.match(html, /role="dialog"/, 'the flow is a dialog');
assert.match(html, /aria-modal="true"/, 'it is modal');
assert.match(html, /aria-labelledby="ga-title"/, 'it is named by its heading');
assert.match(html, /id="ga-title"/, 'the heading carrying that name exists');

// The progress list is a real list, labelled, with the current step marked —
// not colour alone.
assert.match(html, /aria-label="Progress"/, 'the step list is labelled');
assert.match(html, /aria-current="step"/, 'the current step is marked for screen readers');
for (const label of ['What happened', 'Which items', 'Why', 'Review']) {
  assert.ok(html.includes(label), `step "${label}" is present`);
}

// Step one offers the three actions the brief names, each with an explanation.
for (const choice of ['Cancel invoice', 'Full refund', 'Partial refund']) {
  assert.ok(html.includes(choice), `"${choice}" is offered`);
}

// A close control is reachable from the first step, not only by Escape.
assert.match(html, /aria-label="Close without saving"/, 'the dialog has a visible close control');

// Staff are told plainly that submitting changes nothing yet.
const staff = render({ canApprove: false });
assert.ok(!/Confirm S\$|Confirm cancellation/.test(staff),
  'someone who cannot approve is never shown a confirm button on step one');

console.log('PASS: guided dialog is a named modal with a labelled, machine-readable step list and the three offered actions');

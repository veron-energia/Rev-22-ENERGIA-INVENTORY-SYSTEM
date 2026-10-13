// Render the actual claim panel with a fake read-only backend. Reports the
// current UI; this is an acceptance audit, not a passing regression assertion.
import { JSDOM } from 'jsdom';
import { build } from 'esbuild';
const dom = new JSDOM('<div id="root"></div>', { url: 'https://tests.invalid' });
for (const key of ['window', 'document', 'navigator', 'HTMLElement', 'Element', 'Node', 'Event']) {
  Object.defineProperty(globalThis, key, { value: dom.window[key], configurable: true, writable: true });
}
globalThis.IS_REACT_ACT_ENVIRONMENT = true;
globalThis.__voucherAuditBackend = { rpc: async () => ({ error: null, data: {
  entitlement_id: 'audit', entitlement_no: 'AUDIT', package_name: 'Test package',
  entitled: 10, claimed: 0, revoked: 0, remaining: 10,
  claim_deadline: '2027-09-15', deadline_passed: false, cancelled: false,
  status: 'pending_activation', snapshot_present: true,
  eligible: [
    { voucher_id: 'facial', name: 'Facial Voucher', available: 20, still_offered: true },
    { voucher_id: 'massage', name: 'Massage Voucher', available: 20, still_offered: true },
  ],
} }) };
const built = await build({
  stdin: { contents: `export { VoucherClaimPanel } from './src/components/therapy/VoucherClaimPanel';
    export { createRoot } from 'react-dom/client'; export { default as React, act } from 'react';`,
    loader: 'ts', resolveDir: process.cwd() },
  bundle: true, write: false, format: 'esm', jsx: 'automatic',
  define: { 'process.env.NODE_ENV': '"development"' },
  plugins: [{ name: 'audit-backend', setup(b) {
    b.onResolve({ filter: /(^|\/)supabase$/ }, () => ({ path: 'stub', namespace: 'stub' }));
    b.onLoad({ filter: /.*/, namespace: 'stub' }, () => ({ contents: 'export const supabase = globalThis.__voucherAuditBackend;' }));
    b.onLoad({ filter: /\.css$/ }, () => ({ contents: '', loader: 'js' }));
  } }],
});
const { VoucherClaimPanel, createRoot, React, act } = await import('data:text/javascript;base64,' + Buffer.from(built.outputFiles[0].text).toString('base64'));
const root = createRoot(document.getElementById('root'));
await act(async () => root.render(React.createElement(VoucherClaimPanel, {
  entitlementId: 'audit', canClaim: true, onClose() {},
})));
const fields = [...document.querySelectorAll('input[type="number"]')];
console.log(JSON.stringify({
  exactVoucherChoicesVisibleImmediately: document.body.textContent.includes('Facial Voucher') && document.body.textContent.includes('Massage Voucher'),
  numberInputCount: fields.length,
  numberInputsInVoucherRows: fields.filter(x => x.closest('tbody tr')).length,
  separateTotalQuantityInput: fields.some(x => !x.closest('tbody tr')),
  result: fields.some(x => !x.closest('tbody tr')) ? 'REVIEW' : 'FAIL: no quantity-first step; exact voucher choices are presented immediately',
}, null, 2));
await act(async () => root.unmount());
dom.window.close();
// The bundled React development scheduler retains its Node message channel.
// All rendering and cleanup have finished; do not leave the audit running.
process.exit(0);

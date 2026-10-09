// What the pages say about a staff login when its profile is switched off or
// on (412). The database signs the login out and blocks it in the same save;
// the Users & Roles page says so, sends Active only when the dialog changed
// it (and only onto the state it was opened with), locks the box for invited
// people, and the sign-in page words the block plainly instead of Supabase
// Auth's "User is banned".
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { build } from 'esbuild';

const built = await build({
  entryPoints: ['src/lib/staffLogin.ts'], bundle: true, write: false, format: 'esm', platform: 'neutral',
});
const mod = await import(`data:text/javascript;base64,${Buffer.from(built.outputFiles[0].text).toString('base64')}`);
const { loginChangeNote, loginChangeHint, signInErrorMessage, isInvitee, activeSaveRefused } = mod;

test('switching Active off says the person is signed out everywhere and cannot sign in', () => {
  assert.equal(loginChangeNote('Sam Staff', true, false),
    'Sam Staff has been signed out on every device and can no longer sign in.');
  assert.equal(loginChangeHint(true, false), 'Saving signs them out on every device and stops them signing in.');
  assert.equal(loginChangeHint(true, false, 'accepted'), 'Saving signs them out on every device and stops them signing in.');
});

test('ticking Active again says the block is lifted, without promising a sign-in a dashboard ban would stop', () => {
  assert.equal(loginChangeNote('Sam Staff', false, true),
    'The sign-in block placed when Sam Staff was switched off has been lifted. '
    + 'They can sign in with their existing password, unless their login was also blocked in the Supabase dashboard.');
  assert.equal(loginChangeHint(false, true),
    'Saving lifts the sign-in block placed when they were switched off. A block placed in the Supabase dashboard stays.');
  assert.equal(loginChangeHint(false, true, null), loginChangeHint(false, true));
});

test('an edit that leaves Active alone says nothing about the login', () => {
  for (const v of [true, false]) {
    assert.equal(loginChangeNote('Sam Staff', v, v), '');
    assert.equal(loginChangeHint(v, v), '');
    assert.equal(loginChangeHint(v, v, 'accepted'), '');
  }
});

test('an invited person is never offered Active: the hint says why, whatever the box shows', () => {
  assert.equal(isInvitee('pending'), true);
  assert.equal(isInvitee('cancelled'), true);
  assert.equal(isInvitee('accepted'), false);
  assert.equal(isInvitee(null), false);
  assert.equal(isInvitee(undefined), false);
  for (const [was, now] of [[false, true], [false, false], [true, false]]) {
    assert.equal(loginChangeHint(was, now, 'pending'), 'An invited person becomes active by accepting their invitation.');
    assert.equal(loginChangeHint(was, now, 'cancelled'), 'Their invitation was cancelled, so they cannot be made active here.');
  }
});

test('a save that changed no row says why: someone else switched them, or the role may not', () => {
  assert.equal(activeSaveRefused('Sam Staff', true),
    'Nothing was saved: someone else switched Sam Staff on or off since you opened this. Close it and open it again.');
  assert.equal(activeSaveRefused('Sam Staff', false),
    "Nothing was saved: your role cannot change Sam Staff's profile. Ask an Owner.");
});

test('a banned login is told in plain words; other errors pass through', () => {
  const plain = 'This login has been switched off. Ask an Owner or Manager if you need access.';
  assert.equal(signInErrorMessage({ message: 'User is banned', code: 'user_banned' }), plain);
  assert.equal(signInErrorMessage({ message: 'User is banned' }), plain);
  assert.equal(signInErrorMessage({ message: 'Invalid login credentials', code: 'invalid_credentials' }),
    'Invalid login credentials');
});

test('the Users page sends Active only when the dialog changed it, onto the state it was opened with', () => {
  const src = readFileSync('src/pages/UsersPage.tsx', 'utf8');
  assert.match(src, /const activeChanged = form\.is_active !== editUser\.is_active;/);
  assert.match(src, /\.\.\.\(activeChanged \? \{ is_active: form\.is_active \} : \{\}\),/);
  assert.match(src, /if \(activeChanged\) update = update\.eq\('is_active', editUser\.is_active\);/);
  assert.match(src, /await update\.select\('id, is_active'\)/);
  // The old whole-row save sent the dialog's Active with every edit.
  assert.doesNotMatch(src, /role: form\.role, is_active: form\.is_active/);
  assert.doesNotMatch(src, /^\s*is_active: form\.is_active,/m);
});

test('the Users page words the notice from the saved row, and only for a change this save made', () => {
  const src = readFileSync('src/pages/UsersPage.tsx', 'utf8');
  assert.match(src, /const note = activeChanged\s*\?\s*loginChangeNote\(name, editUser\.is_active, \(saved\[0\] as \{ is_active: boolean \}\)\.is_active\)\s*:\s*'';/);
  assert.match(src, /setErr\(activeSaveRefused\(editUser\.full_name, changedElsewhere\)\);/);
  assert.match(src, /changedElsewhere = !!current && \(current as \{ is_active: boolean \}\)\.is_active !== editUser\.is_active;/);
});

test('the Users page locks the Active box for invited people and shows the hint for their state', () => {
  const src = readFileSync('src/pages/UsersPage.tsx', 'utf8');
  assert.match(src, /disabled=\{isInvitee\(editUser\.invitation_status\)\}/);
  assert.match(src, /loginChangeHint\(editUser\.is_active, form\.is_active, editUser\.invitation_status\)/);
  const types = readFileSync('src/types/index.ts', 'utf8');
  assert.match(types, /invitation_status\?: string \| null;/);
});

test('the staff sign-in goes through the plain wording', () => {
  const src = readFileSync('src/context/AuthContext.tsx', 'utf8');
  assert.match(src, /if \(signInErr\) return \{ error: signInErrorMessage\(signInErr\) \};/);
});

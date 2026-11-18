// Source scan (security audit of 17 Nov 2026, L10): no reply may carry the names
// of missing secrets, and the invitation code may not build a reply `message`
// from a database or provider error. Cheap to run, and it fails the day someone
// puts the old line back.

import { assertEquals } from 'jsr:@std/assert@1';

const functionsDir = new URL('../../../', import.meta.url);   // supabase/functions/
const sharedDir = new URL('../', import.meta.url);            // _shared/auth-email/

async function sources(): Promise<{ name: string; text: string }[]> {
  const files: URL[] = [];
  for await (const entry of Deno.readDir(functionsDir)) {
    if (entry.isDirectory && !entry.name.startsWith('_')) {
      const index = new URL(`${entry.name}/index.ts`, functionsDir);
      try { await Deno.stat(index); files.push(index); } catch { /* no index.ts */ }
    }
  }
  for await (const entry of Deno.readDir(sharedDir)) {
    if (entry.isFile && entry.name.endsWith('.ts')) files.push(new URL(entry.name, sharedDir));
  }
  return await Promise.all(files.map(async u => ({ name: u.pathname, text: await Deno.readTextFile(u) })));
}

Deno.test('no reply names the missing secrets', async () => {
  const offenders: string[] = [];
  for (const { name, text } of await sources()) {
    if (/missing:\s*error\.names/.test(text)) offenders.push(`${name}: missing: error.names`);
    if (/json\([^;]*\bmissing:/.test(text)) offenders.push(`${name}: missing: inside json(`);
  }
  assertEquals(offenders, []);
});

Deno.test('invitations.ts builds no message from a database error', async () => {
  const text = await Deno.readTextFile(new URL('invitations.ts', sharedDir));
  const offenders = text.split('\n').filter(line =>
    /\bmessage:\s*[^,}]*(\.error\??\.message|error\?\.message)/.test(line));
  assertEquals(offenders, []);
  // The one place that mentions an error beside a message keeps it out of it.
  assertEquals(/\$\{[^}]*error\??\.message[^}]*\}/.test(text), false);
});

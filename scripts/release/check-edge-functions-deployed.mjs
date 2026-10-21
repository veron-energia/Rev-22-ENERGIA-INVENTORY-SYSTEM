// Release check: every Edge Function in supabase/functions is deployed.
//
// Why: the audit of 9 Oct 2026 (ADMIN-AUTH-1) found auth-accept-invitation in
// the repository but not deployed, so no invited member of staff could finish
// setting up. Nobody had noticed, because nothing compared the two lists.
//
// What it checks: names only. Each folder in supabase/functions must be in the
// deployed list. Two kinds of folder are not checked:
//   * _shared, which holds code the functions share (and any other folder
//     whose name starts with "_" or ".");
//   * auth-email-hook, which is kept out of git and is never deployed from here.
// A function that is deployed but has no folder here is listed. That is not a
// failure.
//
// It only reads. It never deploys, and it changes nothing anywhere.
//
// How to run it, from the repository's root:
//   npm run check:edge-functions
//     Runs `supabase functions list -o json`, which only reads. It uses your
//     own Supabase CLI login (`supabase login`), so no key is kept in the
//     repository. In a folder that is not linked to the project (a git
//     worktree is not), add the project ref:
//       npm run check:edge-functions -- --project-ref <ref>
//     or set SUPABASE_PROJECT_REF. If the CLI gives no answer in 90 seconds,
//     the check stops; then use --from.
//   node scripts/release/check-edge-functions-deployed.mjs --from <file>
//     Reads a list saved another way: the JSON from
//     `supabase functions list -o json`, the result of the Supabase MCP tool
//     list_edge_functions, the table `supabase functions list` prints, or one
//     name per line. Use --from - to read it from standard input.
//   npm run test:release
//     Checks this script with made-up lists. It needs no network.
//
// It prints each folder that is not deployed and exits 1. When every folder is
// deployed it says so and exits 0. It exits 2 when it cannot read the list.
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readdirSync, readFileSync, realpathSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT = fileURLToPath(import.meta.url);
const FUNCTIONS_DIR = fileURLToPath(new URL('../../supabase/functions', import.meta.url));
// Folders that are not checked by name (see the top of this file).
const NOT_CHECKED = new Set(['auth-email-hook']);
const NAME = /^[A-Za-z0-9][A-Za-z0-9_-]*$/;
const CLI_TIMEOUT_MS = 90_000;

class ListError extends Error {}

export function localFunctionNames(dir = FUNCTIONS_DIR) {
  let entries;
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch {
    throw new ListError(`There is no functions folder at ${dir}.`);
  }
  return entries
    .filter((e) => e.isDirectory() && !e.name.startsWith('_') && !e.name.startsWith('.') && !NOT_CHECKED.has(e.name))
    .map((e) => e.name)
    .sort();
}

// The deployed names, from any of the forms described at the top.
export function deployedNames(text) {
  const body = String(text ?? '').trim();
  if (!body) throw new ListError('The deployed list is empty. Nothing was read.');
  if (body.startsWith('[') || body.startsWith('{')) {
    let data;
    try { data = JSON.parse(body); } catch { data = undefined; }
    if (data !== undefined) return unique(namesFromJson(data));
  }
  return unique(namesFromText(body));
}

function namesFromJson(data) {
  const list = findList(data, 0);
  if (!list) throw new ListError('The JSON has no list of functions in it.');
  return list.map((f) => {
    const name = typeof f === 'string' ? f : (f?.slug ?? f?.name);
    if (typeof name !== 'string' || !NAME.test(name)) {
      throw new ListError(`A function in the list has no readable name: ${JSON.stringify(f).slice(0, 80)}`);
    }
    return name;
  });
}

// An array, or an object that holds one (the MCP result may wrap it, even as
// a JSON string). A saved MCP tools/call result holds the list as JSON text
// inside its content parts: {content: [{type: 'text', text: '[...]'}]}.
function findList(data, depth) {
  if (Array.isArray(data)) {
    const textParts = data.length > 0 && data.every((x) => x && typeof x === 'object' && x.type === 'text' && typeof x.text === 'string');
    if (!textParts) return data;
    for (const x of data) {
      const found = findList(x.text, depth + 1);
      if (found) return found;
    }
    return null;
  }
  if (depth > 5) return null;
  if (typeof data === 'string') {
    const s = data.trim();
    if (!s.startsWith('[') && !s.startsWith('{')) return null;
    try { return findList(JSON.parse(s), depth + 1); } catch { return null; }
  }
  if (data && typeof data === 'object') {
    const keys = ['functions', 'result', 'data', 'items', 'content', 'text'];
    for (const k of [...keys.filter((k) => k in data), ...Object.keys(data).filter((k) => !keys.includes(k))]) {
      const found = findList(data[k], depth + 1);
      if (found) return found;
    }
  }
  return null;
}

function namesFromText(body) {
  const lines = body.split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
  if (lines.some((l) => l.includes('|'))) {
    // The table `supabase functions list` prints: a header row, a rule, rows.
    const rows = lines.filter((l) => l.includes('|') && !/^[-|+\s]+$/.test(l)).map((l) => l.split('|').map((c) => c.trim()));
    if (!rows.length) throw new ListError('The table has no rows.');
    const header = rows[0].map((c) => c.toUpperCase());
    const col = header.indexOf('SLUG') >= 0 ? header.indexOf('SLUG') : header.indexOf('NAME');
    if (col < 0) throw new ListError('The table has no SLUG or NAME column.');
    return rows.slice(1).map((r) => {
      if (!NAME.test(r[col] ?? '')) throw new ListError(`This row has no readable name: ${r.join(' | ').slice(0, 80)}`);
      return r[col];
    });
  }
  return lines.map((l) => {
    if (!NAME.test(l)) throw new ListError(`This line is not a function name: ${l.slice(0, 80)}`);
    return l;
  });
}

function unique(names) {
  return [...new Set(names)].sort();
}

export function compare(local, deployed) {
  const have = new Set(deployed);
  const mine = new Set(local);
  return {
    missing: local.filter((n) => !have.has(n)),
    extra: deployed.filter((n) => !mine.has(n)),
  };
}

function listWithCli(projectRef) {
  const args = ['functions', 'list', '-o', 'json'];
  if (projectRef) args.push('--project-ref', projectRef);
  const r = spawnSync('supabase', args, { encoding: 'utf8', timeout: CLI_TIMEOUT_MS });
  if (r.error?.code === 'ENOENT') throw new ListError('The Supabase CLI is not installed. Save the list another way and use --from.');
  if (r.error || r.signal) {
    throw new ListError(`supabase functions list did not answer in ${CLI_TIMEOUT_MS / 1000} seconds. Save the list another way and use --from.`);
  }
  if (r.status !== 0) {
    throw new ListError(`supabase functions list failed:\n${(r.stderr || r.stdout || '').trim()}\n` +
      'Sign in with `supabase login`, and give --project-ref when this folder is not linked.');
  }
  return r.stdout;
}

function parseArgs(argv) {
  const opts = { from: null, projectRef: process.env.SUPABASE_PROJECT_REF || null, functionsDir: FUNCTIONS_DIR, selfTest: false };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    const value = () => {
      const v = argv[i + 1];
      if (v === undefined) throw new ListError(`${a} needs a value.`);
      i += 1;
      return v;
    };
    if (a === '--from') opts.from = value();
    else if (a === '--project-ref') opts.projectRef = value();
    else if (a === '--functions-dir') opts.functionsDir = value();
    else if (a === '--self-test') opts.selfTest = true;
    else throw new ListError(`Unknown option ${a}. See the top of ${SCRIPT}.`);
  }
  return opts;
}

// A list file that cannot be read stops the check as unreadable (exit 2),
// never as a stack trace.
function readList(from) {
  try {
    return readFileSync(from === '-' ? 0 : from, 'utf8');
  } catch (e) {
    throw new ListError(`Could not read the deployed list from ${from === '-' ? 'standard input' : from} (${e.code || e.message}).`);
  }
}

export function run(argv, out = console.log) {
  const opts = parseArgs(argv);
  const local = localFunctionNames(opts.functionsDir);
  const text = opts.from === null ? listWithCli(opts.projectRef) : readList(opts.from);
  const deployed = deployedNames(text);
  const { missing, extra } = compare(local, deployed);
  if (extra.length) out(`Deployed, with no folder checked here (not a failure): ${extra.join(', ')}.`);
  if (missing.length) {
    out(`Not deployed (${missing.length} of ${local.length} function folders):`);
    for (const n of missing) out(`  ${n}: deploy it with supabase functions deploy ${n}, after its migration, as its batch says.`);
    return 1;
  }
  out(`All ${local.length} function folders are deployed: ${local.join(', ')}.`);
  return 0;
}

// Made-up lists only. Every check prints one line.
async function selfTest() {
  const { default: assert } = await import('node:assert/strict');
  const dir = mkdtempSync(join(tmpdir(), 'edge-fn-check-'));
  let passed = 0;
  const check = (name, fn) => { fn(); passed += 1; console.log(`ok ${passed} ${name}`); };
  try {
    const fns = join(dir, 'functions');
    for (const d of ['_shared', '.cache', 'auth-email-hook', 'admin-invite-user', 'auth-accept-invitation', 'web-ticket-order']) {
      mkdirSync(join(fns, d), { recursive: true });
    }
    writeFileSync(join(fns, 'README.md'), 'not a function');
    const fn = (slug) => ({ id: `00000000-0000-4000-8000-${slug.length.toString().padStart(12, '0')}`, slug, name: slug, status: 'ACTIVE', version: 3, verify_jwt: true });
    const cliJson = JSON.stringify([fn('admin-invite-user'), fn('web-ticket-order'), fn('auth-email-hook')], null, 2);
    const allJson = JSON.stringify([fn('admin-invite-user'), fn('auth-accept-invitation'), fn('web-ticket-order')]);

    check('folders: _shared, dot folders, auth-email-hook and files are left out', () => {
      assert.deepEqual(localFunctionNames(fns), ['admin-invite-user', 'auth-accept-invitation', 'web-ticket-order']);
    });
    check('reads the JSON `supabase functions list -o json` prints', () => {
      assert.deepEqual(deployedNames(cliJson), ['admin-invite-user', 'auth-email-hook', 'web-ticket-order']);
    });
    check('reads a wrapped list, as the MCP tool may give it (object, or JSON text inside)', () => {
      assert.deepEqual(deployedNames(JSON.stringify({ functions: [fn('web-ticket-order')] })), ['web-ticket-order']);
      assert.deepEqual(deployedNames(JSON.stringify({ result: allJson })), ['admin-invite-user', 'auth-accept-invitation', 'web-ticket-order']);
      assert.deepEqual(deployedNames(JSON.stringify([{ name: 'only-a-name' }])), ['only-a-name']);
      // The slug is the folder's name; a display name may differ.
      assert.deepEqual(deployedNames(JSON.stringify([{ slug: 'web-ticket-order', name: 'Web ticket order' }])), ['web-ticket-order']);
    });
    check('reads a saved MCP tools/call result: the list is JSON text in a content part', () => {
      const content = [{ type: 'text', text: allJson }];
      const names = ['admin-invite-user', 'auth-accept-invitation', 'web-ticket-order'];
      assert.deepEqual(deployedNames(JSON.stringify({ content })), names);
      assert.deepEqual(deployedNames(JSON.stringify({ jsonrpc: '2.0', id: 1, result: { content } })), names);
      // A content part with no list in it is refused, not taken as "nothing deployed".
      assert.throws(() => deployedNames(JSON.stringify({ content: [{ type: 'text', text: 'Unauthorized' }] })), ListError);
    });
    check('reads the table `supabase functions list` prints', () => {
      const table = [
        '',
        '  ID                                   | NAME              | SLUG              | STATUS | VERSION | UPDATED_AT (UTC)',
        '  -------------------------------------|-------------------|-------------------|--------|---------|---------------------',
        '  00000000-0000-4000-8000-000000000001 | Admin invite      | admin-invite-user | ACTIVE | 3       | 2026-10-01 00:00:00',
        '  00000000-0000-4000-8000-000000000002 | web-ticket-order  | web-ticket-order  | ACTIVE | 6       | 2026-10-10 00:00:00',
        '',
      ].join('\n');
      assert.deepEqual(deployedNames(table), ['admin-invite-user', 'web-ticket-order']);
    });
    check('reads one name per line, skipping blank lines and # notes', () => {
      assert.deepEqual(deployedNames('# saved by hand\nweb-ticket-order\n\nadmin-invite-user\nweb-ticket-order\n'), ['admin-invite-user', 'web-ticket-order']);
    });
    check('a list it cannot read is refused, never taken as "nothing deployed"', () => {
      assert.throws(() => deployedNames(''), ListError);
      assert.throws(() => deployedNames('{"message":"unauthorized"}'), ListError);
      assert.throws(() => deployedNames('[{"id":"x"}]'), ListError);
      assert.throws(() => deployedNames('Error: not logged in'), ListError);
      assert.throws(() => deployedNames('A | B\n1 | 2'), ListError);
    });
    check('the 9 Oct case: a folder that is not deployed is found; an extra deployed one is not a failure', () => {
      assert.deepEqual(compare(localFunctionNames(fns), deployedNames(cliJson)),
        { missing: ['auth-accept-invitation'], extra: ['auth-email-hook'] });
      assert.deepEqual(compare(localFunctionNames(fns), deployedNames(allJson)), { missing: [], extra: [] });
      assert.deepEqual(compare(localFunctionNames(fns), []).missing, ['admin-invite-user', 'auth-accept-invitation', 'web-ticket-order']);
    });
    check('the whole command: exit 1 naming the missing folder, exit 0 when all are deployed, 2 when unreadable or missing', () => {
      const some = join(dir, 'some.json');
      const all = join(dir, 'all.json');
      const bad = join(dir, 'bad.txt');
      writeFileSync(some, cliJson);
      writeFileSync(all, allJson);
      writeFileSync(bad, 'Error: not logged in');
      const node = (args, input) => spawnSync(process.execPath, [SCRIPT, '--functions-dir', fns, ...args], { encoding: 'utf8', input });
      const r1 = node(['--from', some]);
      assert.equal(r1.status, 1, r1.stderr);
      assert.match(r1.stdout, /Not deployed \(1 of 3 function folders\)/);
      assert.match(r1.stdout, /auth-accept-invitation: deploy it/);
      assert.match(r1.stdout, /no folder checked here \(not a failure\): auth-email-hook/);
      const r2 = node(['--from', all]);
      assert.equal(r2.status, 0, r2.stderr);
      assert.match(r2.stdout, /All 3 function folders are deployed/);
      const r3 = node(['--from', '-'], allJson);
      assert.equal(r3.status, 0, r3.stderr);
      const r4 = node(['--from', bad]);
      assert.equal(r4.status, 2);
      assert.match(r4.stderr, /not a function name/);
      const r5 = node(['--bogus']);
      assert.equal(r5.status, 2);
      const r6 = spawnSync(process.execPath, [SCRIPT, '--functions-dir', join(dir, 'none'), '--from', all], { encoding: 'utf8' });
      assert.equal(r6.status, 2);
      assert.match(r6.stderr, /There is no functions folder/);
      const r7 = node(['--from', join(dir, 'missing.json')]);
      assert.equal(r7.status, 2, r7.stderr);
      assert.match(r7.stderr, /Could not read the deployed list .*ENOENT/);
      const r8 = node(['--from', dir]);
      assert.equal(r8.status, 2, r8.stderr);
      assert.match(r8.stderr, /Could not read the deployed list .*EISDIR/);
    });
    check('run through a symlinked path, it still checks (on macOS /tmp is a link to /private/tmp)', () => {
      const some = join(dir, 'some.json');
      writeFileSync(some, cliJson);
      const fileLink = join(dir, 'linked-check.mjs');
      const dirLink = join(dir, 'linked-release');
      symlinkSync(SCRIPT, fileLink);
      symlinkSync(dirname(SCRIPT), dirLink, 'dir');
      try {
        for (const path of [fileLink, join(dirLink, basename(SCRIPT))]) {
          const r = spawnSync(process.execPath, [path, '--functions-dir', fns, '--from', some], { encoding: 'utf8' });
          assert.equal(r.status, 1, `${path}: ${r.stderr}`);
          assert.match(r.stdout, /Not deployed \(1 of 3 function folders\)/);
        }
      } finally {
        // Remove the links themselves; never what they point at.
        unlinkSync(fileLink);
        unlinkSync(dirLink);
      }
    });
    check('without --from it asks the Supabase CLI for JSON, passing --project-ref; a CLI error is not a pass', () => {
      // A stand-in for the CLI, first on PATH: it saves its arguments and prints a made-up list.
      const bin = join(dir, 'bin');
      mkdirSync(bin);
      const argsFile = join(dir, 'cli-args.txt');
      const listFile = join(dir, 'cli-list.json');
      writeFileSync(listFile, allJson);
      writeFileSync(join(bin, 'supabase'), [
        '#!/bin/sh',
        `printf '%s\\n' "$*" > '${argsFile}'`,
        'if [ "$CLI_FAILS" = yes ]; then echo "Access token not provided" >&2; exit 1; fi',
        `cat '${listFile}'`,
        '',
      ].join('\n'), { mode: 0o755 });
      const cli = (args, extraEnv = {}) => spawnSync(process.execPath, [SCRIPT, '--functions-dir', fns, ...args], {
        encoding: 'utf8',
        env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, SUPABASE_PROJECT_REF: '', ...extraEnv },
      });
      const r1 = cli(['--project-ref', 'madeupref']);
      assert.equal(r1.status, 0, r1.stderr);
      assert.equal(readFileSync(argsFile, 'utf8').trim(), 'functions list -o json --project-ref madeupref');
      const r2 = cli([], { SUPABASE_PROJECT_REF: 'fromenv' });
      assert.equal(r2.status, 0, r2.stderr);
      assert.equal(readFileSync(argsFile, 'utf8').trim(), 'functions list -o json --project-ref fromenv');
      const r3 = cli([], { CLI_FAILS: 'yes' });
      assert.equal(r3.status, 2);
      assert.match(r3.stderr, /supabase functions list failed:\nAccess token not provided/);
    });
    check('the real supabase/functions folder has functions to check, and none is called auth-email-hook', () => {
      const real = localFunctionNames();
      assert.ok(real.length > 0);
      assert.ok(!real.includes('auth-email-hook') && !real.includes('_shared'));
    });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
  console.log(`self-test: ${passed} checks passed`);
}

// Run only when started as a script. Node gives import.meta.url as the real
// path, but process.argv[1] as it was typed, so compare real paths: a path
// through a symlink must not skip the check and exit 0.
const isMain = (() => {
  try { return realpathSync(process.argv[1] ?? '') === realpathSync(SCRIPT); } catch { return false; }
})();
if (isMain) {
  const argv = process.argv.slice(2);
  if (argv.includes('--self-test')) {
    await selfTest();
  } else {
    try {
      process.exitCode = run(argv);
    } catch (e) {
      if (!(e instanceof ListError)) throw e;
      console.error(e.message);
      process.exitCode = 2;
    }
  }
}

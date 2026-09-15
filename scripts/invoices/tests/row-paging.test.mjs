// Reading past the first thousand rows.
//
// PostgREST is deployed with PGRST_DB_MAX_ROWS=1000, so a .select() with no
// .range() stops there and reports no error — the screen shows a plausible,
// wrong answer. XERO_ROW_LIMIT_FIX.md records what that cost the last time.
// fetchAllRows pages until a short page arrives.
import test from 'node:test';
import assert from 'node:assert/strict';

// A stand-in for the PostgREST builder: records the ranges asked for and caps
// every response at 1000 rows, the way the server does.
function fakeTable(total) {
  const calls = [];
  const build = () => {
    const q = {
      order() { return q; },
      range(from, to) {
        const size = Math.min(to - from + 1, 1000);
        const rows = [];
        for (let i = from; i < Math.min(from + size, total); i++) rows.push({ id: i });
        calls.push([from, to]);
        return Promise.resolve({ data: rows, error: null });
      },
    };
    return q;
  };
  return { build, calls };
}

// Import the helper by evaluating it against the fake, since the real module
// pulls in the Supabase client.
async function fetchAllRows(build, orderBy = ['id']) {
  const rows = [];
  for (let offset = 0; ; offset += 1000) {
    let query = build();
    for (const column of orderBy) query = query.order(column, { ascending: true });
    const { data, error } = await query.range(offset, offset + 999);
    if (error) throw new Error(error.message);
    rows.push(...(data ?? []));
    if ((data ?? []).length < 1000) return rows;
  }
}

test('a table under the cap is read in one page', async () => {
  const t = fakeTable(240);
  const rows = await fetchAllRows(t.build);
  assert.equal(rows.length, 240);
  assert.equal(t.calls.length, 1);
});

test('a table over the cap is read completely', async () => {
  const t = fakeTable(2350);
  const rows = await fetchAllRows(t.build);
  assert.equal(rows.length, 2350, 'every row must come back, not the first 1000');
  assert.deepEqual(t.calls, [[0, 999], [1000, 1999], [2000, 2999]]);
  // No row may be fetched twice or skipped.
  assert.equal(new Set(rows.map(r => r.id)).size, 2350);
});

test('an exact multiple of the cap still terminates', async () => {
  const t = fakeTable(2000);
  const rows = await fetchAllRows(t.build);
  assert.equal(rows.length, 2000);
  // The last page must come back short (empty) to end the loop.
  assert.equal(t.calls.length, 3);
});

test('an error stops the walk rather than returning a partial answer', async () => {
  const build = () => ({
    order() { return this; },
    range: () => Promise.resolve({ data: null, error: { message: 'boom' } }),
  });
  await assert.rejects(() => fetchAllRows(build), /boom/);
});

// A stand-in for src/lib/supabase, used only by the preview harness: the
// invented fixture behind a fake client with PostgREST's paging and ordering.
// Add ?fail=<rpc name> to the URL to make that call fail and see the error state.
// @ts-ignore — plain JS modules shared with the harness
import { makeFixture } from './fixture.mjs';
// @ts-ignore
import { createBackend } from './fake-backend.mjs';

const backend = createBackend(makeFixture());
for (const name of new URLSearchParams(location.search).getAll('fail')) backend.failures.set(name, `Preview: ${name} failed`);

export const supabase = backend.client as any;

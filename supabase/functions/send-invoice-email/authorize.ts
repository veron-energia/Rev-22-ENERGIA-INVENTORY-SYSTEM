// Who may email a customer their document.
//
// This lives apart from index.ts so it can be tested without starting a
// server or reaching the network: the decision is the security boundary, and a
// boundary that cannot be tested is a boundary nobody checks.
//
// The rules, in order:
//   1. a bearer token must be present;
//   2. it must resolve to a real user;
//   3. that user must have an active staff profile. The profiles read policy
//      requires a staff role (343), so an affiliate login reads nothing here;
//   4. if the document belongs to a store, the caller must have access to that
//      store, decided by the database through user_has_store_access().
//
// Every question is answered by the database as the caller, so nothing in the
// request body can claim a role.

/** The little of a Supabase client this decision needs. */
export interface CallerClient {
  auth: { getUser(): Promise<{ data: { user: { id: string } | null } | null; error: unknown }> };
  from(table: string): {
    select(cols: string): {
      eq(col: string, val: string): { maybeSingle(): Promise<{ data: unknown; error: unknown }> };
    };
  };
  rpc(fn: string, args: Record<string, unknown>): Promise<{ data: unknown; error: unknown }>;
}

export type Decision =
  | { ok: true; userId: string }
  | { ok: false; status: 401 | 403; error: string };

export function bearerToken(header: string | null): string {
  const h = header ?? '';
  return h.toLowerCase().startsWith('bearer ') ? h.slice(7).trim() : '';
}

export async function authorizeSend(
  caller: CallerClient,
  storeId: string | null | undefined,
): Promise<Decision> {
  const { data: me, error: meError } = await caller.auth.getUser();
  if (meError || !me?.user) {
    return { ok: false, status: 401, error: 'Please sign in again and retry.' };
  }

  const { data: profile } = await caller
    .from('profiles').select('id, is_active').eq('id', me.user.id).maybeSingle();
  const p = profile as { is_active?: boolean } | null;
  if (!p || p.is_active === false) {
    return { ok: false, status: 403, error: 'Only a member of staff may email a document to a customer.' };
  }

  if (storeId) {
    const { data: allowed, error: accessError } = await caller
      .rpc('user_has_store_access', { target_store_id: storeId });
    if (accessError || allowed !== true) {
      return { ok: false, status: 403, error: 'You do not have access to the store this document belongs to.' };
    }
  }

  return { ok: true, userId: me.user.id };
}

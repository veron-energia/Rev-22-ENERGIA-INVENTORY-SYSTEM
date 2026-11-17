import { useEffect, useState } from 'react';
import { supabase } from './supabase';

// What the portal may show the signed-in affiliate (the Owner, 17 Nov 2026),
// from affiliate_portal_me:
//   'open'       everything, as before;
//   'unproven'   508: the login joined a customer record on the phone number
//                alone and Energia has not confirmed it is theirs yet
//                (link_proven false). The server shows only what the login
//                typed, so the pages say why instead of empty sections;
//   'suspended'  509: the affiliate is suspended, or the account is switched
//                off (portal_closed). The server answers nothing else;
//   'unknown'    not read yet, or the read failed, or a server before 508:
//                the pages show what they read, as before.
export type PortalAccess = 'open' | 'unproven' | 'suspended' | 'unknown';

/** affiliate_portal_me's answer, in one word. */
export function portalAccessOf(me: unknown): PortalAccess {
  if (!me || typeof me !== 'object') return 'unknown';
  const m = me as { portal_closed?: unknown; status?: unknown; link_proven?: unknown };
  // Before 509 the server says "suspended" and still answers: the page hides it all the same.
  if (m.portal_closed === true || m.status === 'suspended') return 'suspended';
  if (m.link_proven === false) return 'unproven';
  return 'open';
}

// The last answer for each login in this tab. Each portal page draws the
// portal shell again, so the next page opens with the right notice straight
// away and reads it again behind.
const lastRead = new Map<string, PortalAccess>();

/** What the portal last found for this login in this tab (null: not read yet). */
export function lastPortalAccess(uid: string | null | undefined): PortalAccess | null {
  return uid ? lastRead.get(uid) ?? null : null;
}

/** Read affiliate_portal_me again for this login. A failed read is 'unknown'. */
export async function readPortalAccess(uid: string): Promise<PortalAccess> {
  const { data, error } = await supabase.rpc('affiliate_portal_me');
  const access = error ? 'unknown' : portalAccessOf(data);
  if (access === 'unknown') lastRead.delete(uid); else lastRead.set(uid, access);
  return access;
}

/**
 * The portal access of the signed-in login: the last answer at once when there
 * is one, read again on each page. null while the first read is on its way.
 */
export function usePortalAccess(uid: string | null): PortalAccess | null {
  const [access, setAccess] = useState<PortalAccess | null>(() => (uid ? lastPortalAccess(uid) : 'unknown'));
  useEffect(() => {
    if (!uid) { setAccess('unknown'); return; }
    let live = true;
    setAccess(lastPortalAccess(uid));
    readPortalAccess(uid).then(a => { if (live) setAccess(a); }, () => { if (live) setAccess('unknown'); });
    return () => { live = false; };
  }, [uid]);
  return access;
}

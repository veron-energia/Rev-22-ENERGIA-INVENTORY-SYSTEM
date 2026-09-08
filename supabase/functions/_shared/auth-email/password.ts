// Changing a password as the signed-in user, not as an administrator.
//
// The notification email is only trustworthy if the change is something this
// server watched happen. So the server performs the change itself, through the
// ordinary user-scoped Auth endpoint with the caller's own access token — the
// same request the browser would have made. Everything Supabase enforces still
// applies: the session must be valid, a recovery session works exactly as a
// recovery session should, the project password policy holds, and any
// reauthentication requirement stands.
//
// What is deliberately not used here is the admin user-update API. That would
// let this endpoint set anyone's password on the strength of a request body,
// which is a far larger thing to expose than a notification email is worth.
//
// The new password passes through this function to Supabase and is never
// logged, never stored, and never included in the notification.

export type PasswordChange =
  | { status: 'ok'; userId: string; email: string; displayName: string; changedAt: string }
  | { status: 'unauthorized' }
  | { status: 'rejected'; message: string }
  | { status: 'error'; message: string };

export async function changeOwnPassword(
  args: { supabaseUrl: string; apiKey: string; accessToken: string; password: string },
  fetchImpl: typeof fetch = fetch,
): Promise<PasswordChange> {
  let response: Response;
  try {
    response = await fetchImpl(`${args.supabaseUrl}/auth/v1/user`, {
      method: 'PUT',
      headers: {
        apikey: args.apiKey,
        Authorization: `Bearer ${args.accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ password: args.password }),
    });
  } catch (error) {
    return { status: 'error', message: `auth request failed: ${String(error)}` };
  }

  const body = await response.json().catch(() => ({}));

  if (response.status === 401 || response.status === 403) return { status: 'unauthorized' };
  if (!response.ok) {
    // Supabase's own wording, passed through. The caller is the account holder,
    // so "New password should be different from the old password" or a policy
    // failure is exactly what they need to read.
    const message = typeof body?.msg === 'string' ? body.msg
      : typeof body?.message === 'string' ? body.message
        : typeof body?.error_description === 'string' ? body.error_description
          : 'Could not update the password.';
    return { status: 'rejected', message };
  }

  const id = typeof body?.id === 'string' ? body.id : '';
  const email = typeof body?.email === 'string' ? body.email : '';
  if (!id || !email) return { status: 'error', message: 'password updated but the account could not be read back' };

  const meta = (body?.user_metadata ?? {}) as Record<string, unknown>;
  const displayName = [meta.first_name, meta.last_name]
    .filter(v => typeof v === 'string' && v.trim())
    .join(' ')
    .trim();

  return {
    status: 'ok',
    userId: id,
    email,
    displayName,
    changedAt: typeof body?.updated_at === 'string' ? body.updated_at : new Date().toISOString(),
  };
}

/** The bearer token, or null. Never logged. */
export function bearerToken(req: Request): string | null {
  const header = req.headers.get('authorization') ?? '';
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  const token = match?.[1]?.trim() ?? '';
  // The anon/publishable key is what supabase-js sends when there is no session;
  // it is not a user token and must not be treated as one.
  if (!token || !token.includes('.') || token.startsWith('sb_')) return null;
  return token;
}

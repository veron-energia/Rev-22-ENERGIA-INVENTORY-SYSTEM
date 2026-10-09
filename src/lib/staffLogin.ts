// What happens to a member of staff's login when their profile is switched
// off or on (412). The database does it, in the same save: switching a
// profile off ends every session of that login and blocks it from signing
// in; switching it on again lifts that block. A block placed some other way
// (the Supabase dashboard) stays. These are the plain words the pages use to
// say so.

/**
 * An invited person (invitation pending or cancelled). The database does not
 * let a page switch them on: they become active by accepting their invitation.
 */
export function isInvitee(invitationStatus: string | null | undefined): boolean {
  return (invitationStatus ?? 'accepted') !== 'accepted';
}

/** The sentence added to "X's profile was saved." when this save changed Active. */
export function loginChangeNote(name: string, wasActive: boolean, isActive: boolean): string {
  if (wasActive && !isActive) {
    return `${name} has been signed out on every device and can no longer sign in.`;
  }
  if (!wasActive && isActive) {
    return `The sign-in block placed when ${name} was switched off has been lifted. `
      + 'They can sign in with their existing password, unless their login was also blocked in the Supabase dashboard.';
  }
  return '';
}

/**
 * Shown under the Active tick box. For an invitee the box cannot be ticked,
 * so it says why; otherwise only when the box differs from the saved state.
 */
export function loginChangeHint(wasActive: boolean, isActive: boolean, invitationStatus?: string | null): string {
  if (invitationStatus === 'pending') return 'An invited person becomes active by accepting their invitation.';
  if (isInvitee(invitationStatus)) return 'Their invitation was cancelled, so they cannot be made active here.';
  if (wasActive && !isActive) return 'Saving signs them out on every device and stops them signing in.';
  if (!wasActive && isActive) {
    return 'Saving lifts the sign-in block placed when they were switched off. '
      + 'A block placed in the Supabase dashboard stays.';
  }
  return '';
}

/**
 * When the save of Active changed no row. Either someone else switched this
 * person on or off since the dialog opened (the save only applies to the
 * state it was opened with), or this login's role may not edit them.
 */
export function activeSaveRefused(name: string, changedElsewhere: boolean): string {
  return changedElsewhere
    ? `Nothing was saved: someone else switched ${name} on or off since you opened this. Close it and open it again.`
    : `Nothing was saved: your role cannot change ${name}'s profile. Ask an Owner.`;
}

/**
 * The sign-in page's words for an error from Supabase Auth. A login whose
 * staff profile is switched off is banned there, and "User is banned" says
 * nothing useful to the person reading it.
 */
export function signInErrorMessage(error: { message: string; code?: string | null }): string {
  if (error.code === 'user_banned' || /\bbanned\b/i.test(error.message)) {
    return 'This login has been switched off. Ask an Owner or Manager if you need access.';
  }
  return error.message;
}

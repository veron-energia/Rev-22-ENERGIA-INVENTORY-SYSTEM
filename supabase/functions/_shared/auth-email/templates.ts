// The three Auth emails, as HTML and plain text.
//
// Inline styles only and a single-column layout under 600px: Gmail strips
// <style> blocks in a lot of clients, and these are read on phones at roadshows.
// Every interpolated value goes through `escapeHtml`, and the action link is
// checked against this project's Auth origin by the caller before it gets here.

export type AuthEmailAction = 'verify_signup' | 'password_recovery' | 'password_changed' | 'user_invitation';

export interface RenderedEmail {
  subject: string;
  html: string;
  text: string;
}

export const SUBJECTS: Record<AuthEmailAction, string> = {
  verify_signup: 'Verify Your Energia Affiliate Account',
  password_recovery: 'Reset Your Energia Password',
  password_changed: 'Your Energia Password Was Changed',
  user_invitation: "You're Invited to Energia",
};

const BRAND = '#1f7a4d';
const INK = '#111827';
const MUTED = '#6b7280';

export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Strip anything that could break out of a header line. Applied to every value
 * that ends up in a subject, a recipient or a sender name, so a display name
 * carrying a newline cannot inject a header downstream.
 */
export function headerSafe(value: string, max = 200): string {
  return value.replace(/[\r\n\t]+/g, ' ').replace(/\s+/g, ' ').trim().slice(0, max);
}

const greeting = (name: string): string => {
  const clean = headerSafe(name, 60);
  return clean ? `Hi ${clean},` : 'Hi,';
};

function shell(bodyHtml: string): string {
  return `<div style="margin:0;padding:0;background:#f4f6f5;">
  <div style="max-width:560px;margin:0 auto;padding:24px 16px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
    <div style="text-align:center;padding-bottom:18px;">
      <span style="display:inline-block;font-size:19px;font-weight:700;color:${BRAND};letter-spacing:.2px;">Energia</span>
    </div>
    <div style="background:#ffffff;border-radius:12px;padding:26px 22px;border:1px solid #e5e7eb;">
      ${bodyHtml}
    </div>
    <p style="margin:18px 4px 0;font-size:12px;line-height:1.6;color:${MUTED};text-align:center;">
      Rev 22 Global Energia<br>
      This is an automated message about your Energia account.
    </p>
  </div>
</div>`;
}

/**
 * Takes the raw link and escapes it once — for the attribute and for the
 * visible copy-paste text alike. Escaping it before it gets here would double it
 * up, and the fallback line is exactly the one people reach for when the button
 * fails, so a `&amp;` sitting in the middle of the URL they copy is the last
 * thing that should be there.
 */
function button(link: string, label: string): string {
  const href = escapeHtml(link);
  return `<p style="margin:22px 0;text-align:center;">
      <a href="${href}" style="display:inline-block;background:${BRAND};color:#ffffff;text-decoration:none;font-size:15px;font-weight:600;padding:13px 26px;border-radius:9px;">${escapeHtml(label)}</a>
    </p>
    <p style="margin:0 0 4px;font-size:12.5px;line-height:1.6;color:${MUTED};">
      If the button does not work, copy this link into your browser:
    </p>
    <p style="margin:0;font-size:12.5px;line-height:1.6;word-break:break-all;">
      <a href="${href}" style="color:${BRAND};">${href}</a>
    </p>`;
}

const p = (text: string): string =>
  `<p style="margin:0 0 14px;font-size:15px;line-height:1.65;color:${INK};">${text}</p>`;

const h = (text: string): string =>
  `<h1 style="margin:0 0 14px;font-size:20px;line-height:1.35;color:${INK};font-weight:700;">${escapeHtml(text)}</h1>`;

export function renderVerifySignup(name: string, actionLink: string): RenderedEmail {
  return {
    subject: SUBJECTS.verify_signup,
    html: shell(
      h('Verify your affiliate account') +
      p(escapeHtml(greeting(name))) +
      p('Thanks for signing up as an Energia Affiliate. Confirm your email address to finish setting up your account.') +
      button(actionLink, 'Verify My Account') +
      `<p style="margin:18px 0 0;font-size:12.5px;line-height:1.6;color:${MUTED};">
        This link can only be used once and expires after a while. If you did not sign up for an Energia Affiliate account, you can ignore this email.
      </p>`,
    ),
    text: [
      greeting(name), '',
      'Thanks for signing up as an Energia Affiliate. Confirm your email address',
      'to finish setting up your account:', '',
      actionLink, '',
      'This link can only be used once and expires after a while.',
      'If you did not sign up for an Energia Affiliate account, you can ignore this email.', '',
      'Rev 22 Global Energia',
    ].join('\n'),
  };
}

/**
 * The invitation an internal user receives.
 *
 * No password, no temporary credential and no secret of any kind is in this
 * email — the recipient chooses their own password on arrival, which is why
 * there is nothing here for a forwarded message to leak.
 *
 * Expiry is described only as far as it is actually true. Supabase's link
 * lifetime is a project setting, so this says the link is single-use and can be
 * re-sent rather than naming a number of hours the configuration might not
 * match.
 *
 * The role is deliberately absent. It is decided by the administrator and
 * enforced on the server; printing it here would only invite a reply arguing
 * about it, and would put internal structure into an email that may be
 * forwarded.
 */
export function renderUserInvitation(name: string, actionLink: string, invitedBy?: string): RenderedEmail {
  const from = invitedBy && invitedBy.trim()
    ? ` by ${escapeHtml(invitedBy.trim())}`
    : '';
  const fromText = invitedBy && invitedBy.trim() ? ` by ${invitedBy.trim()}` : '';
  return {
    subject: SUBJECTS.user_invitation,
    html: shell(
      h("You're invited to Energia") +
      p(escapeHtml(greeting(name))) +
      p(`You have been invited${from} to use the Energia inventory and sales system. ` +
        'Set up your account to get started — you will choose your own password, ' +
        'and nobody else will know it.') +
      button(actionLink, 'Set Up My Account') +
      `<p style="margin:18px 0 0;font-size:12.5px;line-height:1.6;color:${MUTED};">
        This link can only be used once. If it stops working, ask whoever invited you to send a new one.
      </p>` +
      `<p style="margin:10px 0 0;font-size:12.5px;line-height:1.6;color:${MUTED};">
        If you were not expecting this invitation, you can ignore this email — no account is active until
        someone sets a password, and you can reply to this message to let us know.
      </p>`,
    ),
    text: [
      greeting(name), '',
      `You have been invited${fromText} to use the Energia inventory and sales system.`,
      'Set up your account here. You will choose your own password.', '',
      actionLink, '',
      'This link can only be used once. If it stops working, ask whoever invited',
      'you to send a new one.', '',
      'If you were not expecting this invitation you can ignore this email. No',
      'account is active until someone sets a password, and you can reply to this',
      'message to let us know.', '',
      'Rev 22 Global Energia',
    ].join('\n'),
  };
}

export function renderPasswordRecovery(name: string, actionLink: string): RenderedEmail {
  return {
    subject: SUBJECTS.password_recovery,
    html: shell(
      h('Reset your password') +
      p(escapeHtml(greeting(name))) +
      p('We received a request to reset the password for your Energia account. Choose a new password using the link below.') +
      button(actionLink, 'Reset My Password') +
      `<p style="margin:18px 0 0;font-size:12.5px;line-height:1.6;color:${MUTED};">
        This link can only be used once and expires after a while. If you did not ask to reset your password, you can ignore this email — your password will not change.
      </p>`,
    ),
    text: [
      greeting(name), '',
      'We received a request to reset the password for your Energia account.',
      'Choose a new password here:', '',
      actionLink, '',
      'This link can only be used once and expires after a while.',
      'If you did not ask to reset your password, you can ignore this email —',
      'your password will not change.', '',
      'Rev 22 Global Energia',
    ].join('\n'),
  };
}

/**
 * Sent after a password change that this server carried out and Supabase
 * confirmed. It carries no link and no token on purpose: there is nothing to
 * click, so there is nothing to phish, and a stolen copy grants nothing.
 */
export function renderPasswordChanged(name: string, whenIso: string, supportEmail: string): RenderedEmail {
  const when = formatWhen(whenIso);
  return {
    subject: SUBJECTS.password_changed,
    html: shell(
      h('Your password was changed') +
      p(escapeHtml(greeting(name))) +
      p(`The password for your Energia account was changed on <strong>${escapeHtml(when)}</strong>.`) +
      p('If that was you, there is nothing to do.') +
      p(`If it was not you, please contact us straight away at <a href="mailto:${escapeHtml(supportEmail)}" style="color:${BRAND};">${escapeHtml(supportEmail)}</a>.`),
    ),
    text: [
      greeting(name), '',
      `The password for your Energia account was changed on ${when}.`, '',
      'If that was you, there is nothing to do.',
      `If it was not you, please contact us straight away at ${supportEmail}.`, '',
      'Rev 22 Global Energia',
    ].join('\n'),
  };
}

/** UTC, spelled out. Recipients are in SGT/MYT; an explicit zone beats a guess. */
export function formatWhen(iso: string): string {
  const at = new Date(iso);
  if (Number.isNaN(at.getTime())) return 'recently';
  return `${at.toISOString().slice(0, 16).replace('T', ' ')} UTC`;
}

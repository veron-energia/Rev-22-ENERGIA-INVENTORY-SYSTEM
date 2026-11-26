// Pure, runtime-agnostic template + delivery-building logic for the Supabase
// Send Email Auth Hook. NO Deno APIs are used here so this file can be unit
// tested under Node (see templates.test.ts). index.ts (Deno) does the signed
// webhook verification and the Pabbly HTTP delivery, and imports from here.

export interface HookUser {
  id?: string;
  email?: string;
  new_email?: string;
  user_metadata?: Record<string, unknown>;
}

export interface HookEmailData {
  token?: string;
  token_hash?: string;
  token_new?: string;
  token_hash_new?: string;
  redirect_to?: string;
  email_action_type?: string;
  site_url?: string;
}

export interface HookPayload {
  user: HookUser;
  email_data: HookEmailData;
}

export interface AuthEmailEnv {
  supabaseUrl: string;
  fromName: string;
  fromEmail: string;
  replyTo?: string;
  testRecipient?: string; // if set, ALL mail is redirected here (setup/testing only)
}

export type RecipientRole = 'affiliate' | 'staff' | 'unknown';

export interface AuthEmailDelivery {
  request_id: string;
  action_type: string;
  to: string;
  from_name: string;
  from_email: string;
  reply_to?: string;
  subject: string;
  html: string;
  text: string;
  action_url?: string;
  otp?: string;
  recipient_role: RecipientRole;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
export function escapeHtml(input: unknown): string {
  return String(input ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export function roleOf(user: HookUser): RecipientRole {
  const hint = String(user?.user_metadata?.role_hint ?? '').toLowerCase();
  if (hint === 'affiliate') return 'affiliate';
  if (hint === 'staff') return 'staff';
  return 'unknown';
}

export function firstNameOf(user: HookUser): string | null {
  const fn = user?.user_metadata?.first_name;
  const s = typeof fn === 'string' ? fn.trim() : '';
  return s.length ? s : null;
}

// Supabase owns the token; we only assemble the verify URL that carries it.
export function buildVerifyUrl(supabaseUrl: string, tokenHash: string, type: string, redirectTo?: string): string {
  const base = supabaseUrl.replace(/\/+$/, '');
  let url = `${base}/auth/v1/verify?token=${encodeURIComponent(tokenHash)}&type=${encodeURIComponent(type)}`;
  if (redirectTo) url += `&redirect_to=${encodeURIComponent(redirectTo)}`;
  return url;
}

// ---------------------------------------------------------------------------
// HTML / text rendering (inline styles; ~600px; no external CSS)
// ---------------------------------------------------------------------------
const TEAL = '#0f766e';
const INK = '#1a1f1c';
const MUTED = '#6b7280';

export function renderButton(url: string, label: string): string {
  return (
    `<table role="presentation" cellpadding="0" cellspacing="0" style="margin:24px 0;">` +
    `<tr><td style="border-radius:10px;background:${TEAL};">` +
    `<a href="${escapeHtml(url)}" ` +
    `style="display:inline-block;padding:13px 26px;font-family:Arial,Helvetica,sans-serif;` +
    `font-size:15px;font-weight:700;color:#ffffff;text-decoration:none;border-radius:10px;">` +
    `${escapeHtml(label)}</a></td></tr></table>`
  );
}

interface LayoutParts {
  preheader: string;
  greetingName: string | null;
  bodyLines: string[];   // plain sentences; escaped here
  button?: { url: string; label: string };
  otp?: string;
  footerNote?: string;
}

export function renderLayout(p: LayoutParts): string {
  const greeting = p.greetingName ? `Hi ${escapeHtml(p.greetingName)},` : 'Hi,';
  const paras = p.bodyLines.map(
    (l) => `<p style="margin:0 0 14px;font-size:15px;line-height:1.6;color:${INK};">${escapeHtml(l)}</p>`,
  ).join('');
  const button = p.button ? renderButton(p.button.url, p.button.label) : '';
  const otp = p.otp
    ? `<p style="margin:0 0 8px;font-size:13px;color:${MUTED};">Verification code:</p>` +
      `<p style="margin:0 0 18px;font-size:26px;letter-spacing:4px;font-weight:700;color:${INK};">${escapeHtml(p.otp)}</p>`
    : '';
  const footer = p.footerNote
    ? `<p style="margin:18px 0 0;font-size:13px;line-height:1.6;color:${MUTED};">${escapeHtml(p.footerNote)}</p>`
    : '';

  return (
    `<!doctype html><html><head><meta charset="utf-8">` +
    `<meta name="viewport" content="width=device-width,initial-scale=1"></head>` +
    `<body style="margin:0;padding:0;background:#f6f7f5;">` +
    `<span style="display:none;max-height:0;overflow:hidden;opacity:0;">${escapeHtml(p.preheader)}</span>` +
    `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f6f7f5;padding:24px 12px;">` +
    `<tr><td align="center">` +
    `<table role="presentation" width="600" cellpadding="0" cellspacing="0" ` +
    `style="width:100%;max-width:600px;background:#ffffff;border-radius:14px;border:1px solid #e2e5e0;">` +
    `<tr><td style="padding:24px 28px 8px;">` +
    `<div style="font-family:Arial,Helvetica,sans-serif;font-size:18px;font-weight:800;color:${TEAL};">Rev22 Energia</div>` +
    `</td></tr>` +
    `<tr><td style="padding:8px 28px 28px;font-family:Arial,Helvetica,sans-serif;">` +
    `<p style="margin:0 0 14px;font-size:15px;line-height:1.6;color:${INK};">${greeting}</p>` +
    paras + button + otp +
    `<p style="margin:18px 0 0;font-size:15px;line-height:1.6;color:${INK};">Regards,<br>Rev22 Energia</p>` +
    footer +
    `</td></tr></table>` +
    `<p style="font-family:Arial,Helvetica,sans-serif;font-size:11px;color:${MUTED};margin:16px 0 0;">` +
    `This is an automated message from Rev22 Energia. Please do not reply.</p>` +
    `</td></tr></table></body></html>`
  );
}

function renderText(greetingName: string | null, bodyLines: string[], url: string | undefined, otp: string | undefined, footerNote?: string): string {
  const lines: string[] = [];
  lines.push(greetingName ? `Hi ${greetingName},` : 'Hi,');
  lines.push('');
  for (const l of bodyLines) lines.push(l);
  if (url) { lines.push(''); lines.push(url); }
  if (otp) { lines.push(''); lines.push(`Verification code: ${otp}`); }
  lines.push(''); lines.push('Regards,'); lines.push('Rev22 Energia');
  if (footerNote) { lines.push(''); lines.push(footerNote); }
  return lines.join('\n');
}

// ---------------------------------------------------------------------------
// Copy for each known action type
// ---------------------------------------------------------------------------
interface Copy {
  subject: string;
  bodyLines: string[];
  buttonLabel: string;
  footerNote?: string;
}

function copyFor(actionType: string, role: RecipientRole, opts: { forCurrentEmail?: boolean } = {}): Copy {
  switch (actionType) {
    case 'signup':
      return role === 'affiliate'
        ? { subject: 'Verify Your Energia Affiliate Account',
            bodyLines: ['Thank you for registering as an Energia Affiliate.',
              'Please verify your email address to complete your Affiliate account setup.'],
            buttonLabel: 'Verify My Affiliate Account',
            footerNote: 'If you did not create this account, you can ignore this email.' }
        : { subject: 'Verify Your Energia Account',
            bodyLines: ['Please verify your email address to complete your Energia account setup.'],
            buttonLabel: 'Verify My Email',
            footerNote: 'If you did not create this account, you can ignore this email.' };
    case 'recovery':
      return { subject: 'Reset Your Energia Password',
        bodyLines: ['We received a request to reset your Energia account password.'],
        buttonLabel: 'Reset My Password',
        footerNote: 'If you did not request this reset, you can ignore this email. For security, do not forward this message or share the reset link.' };
    case 'invite':
      return { subject: "You've Been Invited to Energia",
        bodyLines: ['You have been invited to join Energia.', 'Click below to accept your invitation and set up your account.'],
        buttonLabel: 'Accept Invitation' };
    case 'magiclink':
      return { subject: 'Your Energia Sign-In Link',
        bodyLines: ['Use the button below to sign in to your Energia account.'],
        buttonLabel: 'Sign In to Energia',
        footerNote: 'If you did not request this, you can ignore this email.' };
    case 'email_change':
      return opts.forCurrentEmail
        ? { subject: 'Confirm Your Energia Email Change',
            bodyLines: ['We received a request to change the email address for your Energia account.',
              'To authorise this change, please confirm using the button below.'],
            buttonLabel: 'Confirm Email Change',
            footerNote: 'If you did not request this change, please contact Energia immediately.' }
        : { subject: 'Confirm Your Energia Email Change',
            bodyLines: ['Please confirm this email address for your Energia account.'],
            buttonLabel: 'Confirm New Email',
            footerNote: 'If you did not request this change, you can ignore this email.' };
    case 'reauthentication':
      return { subject: 'Confirm Your Energia Account Action',
        bodyLines: ['Please confirm this action on your Energia account using the verification code below.'],
        buttonLabel: 'Confirm',
        footerNote: 'If you did not request this, please contact Energia.' };
    default:
      return { subject: 'Verify Your Energia Account',
        bodyLines: ['Please confirm this request on your Energia account using the button below.'],
        buttonLabel: 'Verify My Email',
        footerNote: 'If you did not request this, you can ignore this email.' };
  }
}

// Actions that primarily carry an OTP code the user may type.
const OTP_ACTIONS = new Set(['magiclink', 'reauthentication']);

// ---------------------------------------------------------------------------
// Build one or two deliveries from a verified hook payload.
// Throws if there is not enough token data to build a safe verification email.
// ---------------------------------------------------------------------------
export function buildDeliveries(payload: HookPayload, env: AuthEmailEnv, requestId: string): AuthEmailDelivery[] {
  const user = payload.user ?? {};
  const ed = payload.email_data ?? {};
  const actionType = String(ed.email_action_type ?? '').trim() || 'unknown';
  const role = roleOf(user);
  const name = firstNameOf(user);

  // -------- Secure email change: two confirmations with reversed mapping ----
  if (actionType === 'email_change' && user.new_email && ed.token_hash && ed.token_hash_new) {
    const currentCopy = copyFor(actionType, role, { forCurrentEmail: true });
    const newCopy = copyFor(actionType, role, { forCurrentEmail: false });
    // CURRENT address: recipient=user.email, OTP=token, hash=token_hash_new
    const currentUrl = buildVerifyUrl(env.supabaseUrl, ed.token_hash_new, 'email_change', ed.redirect_to);
    // NEW address: recipient=user.new_email, OTP=token_new, hash=token_hash
    const newUrl = buildVerifyUrl(env.supabaseUrl, ed.token_hash, 'email_change', ed.redirect_to);
    const out: AuthEmailDelivery[] = [];
    if (user.email) {
      out.push(makeDeliveryFull({ requestId, actionType, to: user.email, role, env, copy: currentCopy, actionUrl: currentUrl, otp: ed.token, greetingName: name }));
    }
    out.push(makeDeliveryFull({ requestId, actionType, to: user.new_email, role, env, copy: newCopy, actionUrl: newUrl, otp: ed.token_new, greetingName: name }));
    return out;
  }

  // -------- All other actions (and single-confirmation email_change) --------
  const recipient = actionType === 'email_change'
    ? (user.new_email || user.email)
    : user.email;

  if (!recipient) throw new Error('no_recipient');

  let actionUrl: string | undefined;
  if (ed.token_hash) {
    actionUrl = buildVerifyUrl(env.supabaseUrl, ed.token_hash, actionType === 'unknown' ? 'signup' : actionType, ed.redirect_to);
  }
  const otp = OTP_ACTIONS.has(actionType) ? ed.token : undefined;

  // We must have SOMETHING actionable (a verify link or an OTP), else bail
  // rather than send a dead email.
  if (!actionUrl && !otp) throw new Error('no_action_data');

  const copy = copyFor(actionType, role, { forCurrentEmail: !user.new_email });
  return [makeDeliveryFull({ requestId, actionType, to: recipient, role, env, copy, actionUrl, otp, greetingName: name })];
}

// Full-typed builder (the earlier makeDelivery kept for readability; this one is used).
function makeDeliveryFull(args: {
  requestId: string; actionType: string; to: string; role: RecipientRole;
  env: AuthEmailEnv; copy: Copy; actionUrl?: string; otp?: string; greetingName: string | null;
}): AuthEmailDelivery {
  const html = renderLayout({
    preheader: args.copy.subject,
    greetingName: args.greetingName,
    bodyLines: args.copy.bodyLines,
    button: args.actionUrl ? { url: args.actionUrl, label: args.copy.buttonLabel } : undefined,
    otp: args.otp,
    footerNote: args.copy.footerNote,
  });
  const text = renderText(args.greetingName, args.copy.bodyLines, args.actionUrl, args.otp, args.copy.footerNote);
  return {
    request_id: args.requestId,
    action_type: args.actionType,
    to: args.env.testRecipient || args.to,
    from_name: args.env.fromName,
    from_email: args.env.fromEmail,
    reply_to: args.env.replyTo,
    subject: args.copy.subject,
    html,
    text,
    action_url: args.actionUrl,
    otp: args.otp,
    recipient_role: args.role,
  };
}

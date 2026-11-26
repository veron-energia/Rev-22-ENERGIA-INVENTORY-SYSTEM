// Supabase Auth "Send Email" hook: it refuses every email.
//
// What it does now: it checks the Standard Webhooks signature (SEND_EMAIL_HOOK_SECRET),
// then sends nothing, whatever the kind:
//   - recovery and magic link, the two kinds a signed-out caller can ask for, are
//     dropped quietly with the success answer (HTTP 200, {}), because the Auth service
//     calls the hook only for an address that has an account, so a refusal would tell
//     the caller whether an address has an account. Success shape: Supabase docs, Send
//     Email Hook, "Outputs" (https://supabase.com/docs/guides/auth/auth-hooks/send-email-hook).
//   - signup, invite, email change, reauthentication and any unknown kind are refused
//     with the error Supabase Auth expects (403), so the Auth API call that triggered
//     the hook fails. It sends no email, calls no other
// service and reads no other setting. One log line per call: fixed words, the email
// kind and the request id, never an address, link, token or code.
//
// Why: nothing in this app makes the Auth service send email itself. Every app email
// goes through the app's own functions (generateLink does not call the hook). So the
// only traffic this hook can get is an email the Auth service sends on its own, such
// as someone calling /auth/v1/recover directly with the public key, which would reach
// any account's inbox outside the app's own sending limits. Security audit of
// 17 Nov 2026 (M6/D7); the owner's decision of 26 Nov 2026: refuse all six kinds.
//
// Version 8 (the Pabbly forwarding code, templates and AUTH_EMAIL_TEST_RECIPIENT)
// is in Git history, commit a88d816, if it is ever wanted back.
//
// JWT verification is OFF for this function (supabase/config.toml): the caller is
// Supabase Auth, and what protects it is the signed webhook.
//   supabase functions deploy auth-email-hook --no-verify-jwt

import { handleHook } from './handler.ts';

Deno.serve((req) => handleHook(req, { hookSecret: Deno.env.get('SEND_EMAIL_HOOK_SECRET') ?? '' }));

// POST /functions/v1/web-ticket-order
//
// Orders from the Alaric Birthday website. The website's Stripe webhook sends
// `paid` when a checkout completes, and /register sends `names` when the buyer
// fills in who is coming. Each becomes one call to a service-role-only database
// function (web_order_paid / web_order_names, migration 372), which records the
// order and, when the channel is live, raises the invoice.
//
// 380: the staff link's registrations come as `door` (web_order_door: kept for
// a Manager to invoice, never invoiced here); `sync` asks for the channel's
// orders with their invoices, the tickets sold at the counter and (382) the
// event's free guests (web_order_sync, at most once a minute); `staff` asks
// for the staff the form may offer as Registered by (web_order_staff).
// 415: `tickets` asks which of the website's passes the app has on sale
// (web_order_tickets), before each checkout and when the ticket page is built,
// so a ticket taken off sale in the app stops selling on the website.
//
// Deploy without gateway JWT verification — the caller is a web server, not a
// signed-in user:
//   supabase functions deploy web-ticket-order --no-verify-jwt
// What protects it instead is an HMAC over the timestamp and the raw body. The
// owner sets the secret in the Supabase function secrets (Dashboard → Edge
// Functions → Secrets, or `supabase secrets set --env-file <file>` so the value
// stays out of shell history) as WEB_ORDER_SIGNING_SECRET, and the same value in
// the website as INVENTORY_ORDER_SECRET. Until it exists every request is
// answered 503 not_configured.
//
// Headers: x-energia-timestamp (unix seconds), x-energia-signature (v1=<hex>).
// Body: { type: 'paid' | 'names' | 'door', order: {...} } or
// { type: 'sync' | 'staff' | 'tickets', channel }. Any other field is a rejected request,
// not an ignored one. See validate.ts for the exact shape.
//
// Nothing from the body is logged: only the type, the Stripe session id (or
// the OFF id, or the channel), the outcome, counts, and how long it took.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.108.2';
import { loadOrderConfig, type OrderConfig } from './config.ts';
import { handleOrder, type RpcClient } from './handler.ts';

const makeClient = (config: OrderConfig): RpcClient =>
  createClient(config.supabaseUrl, config.serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });

Deno.serve((req) => handleOrder(req, { loadConfig: loadOrderConfig, makeClient }));

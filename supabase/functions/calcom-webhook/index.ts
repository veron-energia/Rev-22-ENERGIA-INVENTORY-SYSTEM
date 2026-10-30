// POST /functions/v1/calcom-webhook
//
// cal.com's booking webhook (480, the Owner, 29 Oct 2026). cal.com posts
// BOOKING_CREATED, BOOKING_RESCHEDULED and BOOKING_CANCELLED (and PING when
// the webhook is tested); each booking becomes one call to the
// service-role-only database function calcom_booking_ingest, which stores the
// booking's uid, times, event type and the phone and email it is matched to a
// customer by. The staff Downline and the affiliate portal's My Network show
// it (calcom_customer_bookings).
//
// Deploy without gateway JWT verification (cal.com sends no JWT):
//   supabase functions deploy calcom-webhook --no-verify-jwt
// What protects it instead is cal.com's x-cal-signature-256, an HMAC-SHA256 of
// the raw body with the webhook's secret. The owner sets the secret in the
// Supabase function secrets as CALCOM_WEBHOOK_SECRET (Dashboard -> Edge
// Functions -> Secrets, or `supabase secrets set --env-file <file>` so the
// value stays out of shell history) and the same value in the cal.com
// webhook. Until it exists every request is answered 503 not_configured.
//
// Nothing from the body is logged: only the trigger, the outcome, a SQLSTATE
// and how long it took (see handler.ts).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.108.2';
import { loadWebhookConfig, type WebhookConfig } from './config.ts';
import { handleWebhook, type RpcClient } from './handler.ts';

const makeClient = (config: WebhookConfig): RpcClient =>
  createClient(config.supabaseUrl, config.serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });

Deno.serve((req) => handleWebhook(req, { loadConfig: loadWebhookConfig, makeClient }));

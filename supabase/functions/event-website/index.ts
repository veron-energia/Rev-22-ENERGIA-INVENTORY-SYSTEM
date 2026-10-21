// POST /functions/v1/event-website
//
// An event's own website (436): first the Free Two Day Health Seminar site,
// healthtalk-rev22energia.vercel.app. contract.ts is the API: event_info,
// referral_info, register, person, vip_checkout, vip_paid, vip_transfer,
// vip_refund and sync. Each becomes one call to event_web_call (service role
// only), which checks the key by its SHA-256, the event, the request id and the
// rate, and runs the message.
//
// Deploy without gateway JWT verification: the caller is a web server, not a
// signed-in user, and its key travels in x-energia-key (not Authorization,
// which the gateway owns):
//   supabase functions deploy event-website --no-verify-jwt
// No secret is set for it: the keys are made on the Event page's Website tab
// and kept in the database as hashes. web-ticket-order (the Alaric website) is
// a separate function and is not changed.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.108.2';
import { loadEventWebsiteConfig, type EventWebsiteConfig } from './config.ts';
import { handleRequest, type RpcClient } from './handler.ts';

const makeClient = (config: EventWebsiteConfig): RpcClient =>
  createClient(config.supabaseUrl, config.serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
  });

Deno.serve((req) => handleRequest(req, { loadConfig: loadEventWebsiteConfig, makeClient }));

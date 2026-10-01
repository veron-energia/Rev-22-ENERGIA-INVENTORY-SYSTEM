// Server-side configuration for website orders.
//
// SUPABASE_URL and the service-role key are injected by the platform. The
// signing secret is set by the owner in the Supabase function secrets, and the
// same value goes into the website's INVENTORY_ORDER_SECRET. None of the three
// may appear in a response or a log line.

import { MissingConfigError } from '../_shared/auth-email/config.ts';

export interface OrderConfig {
  supabaseUrl: string;
  serviceRoleKey: string;
  signingSecret: string;
}

const env = (name: string): string => Deno.env.get(name)?.trim() ?? '';

export function loadOrderConfig(): OrderConfig {
  const supabaseUrl = env('SUPABASE_URL');
  // Projects created before the new API keys inject SUPABASE_SERVICE_ROLE_KEY;
  // newer ones inject SUPABASE_SECRET_KEY. Either is the service role.
  const serviceRoleKey = env('SUPABASE_SERVICE_ROLE_KEY') || env('SUPABASE_SECRET_KEY');
  const signingSecret = env('WEB_ORDER_SIGNING_SECRET');

  const missing: string[] = [];
  if (!supabaseUrl) missing.push('SUPABASE_URL');
  if (!serviceRoleKey) missing.push('SUPABASE_SERVICE_ROLE_KEY');
  if (!signingSecret) missing.push('WEB_ORDER_SIGNING_SECRET');
  if (missing.length) throw new MissingConfigError(missing);

  return { supabaseUrl: supabaseUrl.replace(/\/+$/, ''), serviceRoleKey, signingSecret };
}

export { MissingConfigError };

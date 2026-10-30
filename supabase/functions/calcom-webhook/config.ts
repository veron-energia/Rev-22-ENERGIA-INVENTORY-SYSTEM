// Server-side configuration for cal.com's booking webhook (480).
//
// SUPABASE_URL and the service-role key are injected by the platform. The
// webhook secret is set by the owner in the Supabase function secrets as
// CALCOM_WEBHOOK_SECRET, and the same value in cal.com's webhook. None of the
// three may appear in a response or a log line.

import { MissingConfigError } from '../_shared/auth-email/config.ts';

export interface WebhookConfig {
  supabaseUrl: string;
  serviceRoleKey: string;
  webhookSecret: string;
}

const env = (name: string): string => Deno.env.get(name)?.trim() ?? '';

export function loadWebhookConfig(): WebhookConfig {
  const supabaseUrl = env('SUPABASE_URL');
  // Projects created before the new API keys inject SUPABASE_SERVICE_ROLE_KEY;
  // newer ones inject SUPABASE_SECRET_KEY. Either is the service role.
  const serviceRoleKey = env('SUPABASE_SERVICE_ROLE_KEY') || env('SUPABASE_SECRET_KEY');
  const webhookSecret = env('CALCOM_WEBHOOK_SECRET');

  const missing: string[] = [];
  if (!supabaseUrl) missing.push('SUPABASE_URL');
  if (!serviceRoleKey) missing.push('SUPABASE_SERVICE_ROLE_KEY');
  if (!webhookSecret) missing.push('CALCOM_WEBHOOK_SECRET');
  if (missing.length) throw new MissingConfigError(missing);

  return { supabaseUrl: supabaseUrl.replace(/\/+$/, ''), serviceRoleKey, webhookSecret };
}

export { MissingConfigError };

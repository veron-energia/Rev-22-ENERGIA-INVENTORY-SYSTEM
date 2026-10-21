// Server-side configuration for an event's website (436).
//
// SUPABASE_URL and the service-role key are injected by the platform. There is
// no other secret: each event's keys live in the database, as their SHA-256
// only, made on the Event page's Website tab. Neither value may appear in a
// response or a log line.

import { MissingConfigError } from '../_shared/auth-email/config.ts';

export interface EventWebsiteConfig {
  supabaseUrl: string;
  serviceRoleKey: string;
}

const env = (name: string): string => Deno.env.get(name)?.trim() ?? '';

export function loadEventWebsiteConfig(): EventWebsiteConfig {
  const supabaseUrl = env('SUPABASE_URL');
  // Projects created before the new API keys inject SUPABASE_SERVICE_ROLE_KEY;
  // newer ones inject SUPABASE_SECRET_KEY. Either is the service role.
  const serviceRoleKey = env('SUPABASE_SERVICE_ROLE_KEY') || env('SUPABASE_SECRET_KEY');
  const missing: string[] = [];
  if (!supabaseUrl) missing.push('SUPABASE_URL');
  if (!serviceRoleKey) missing.push('SUPABASE_SERVICE_ROLE_KEY');
  if (missing.length) throw new MissingConfigError(missing);
  return { supabaseUrl: supabaseUrl.replace(/\/+$/, ''), serviceRoleKey };
}

export { MissingConfigError };

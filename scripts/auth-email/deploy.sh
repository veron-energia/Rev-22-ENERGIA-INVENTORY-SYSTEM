#!/usr/bin/env bash
# Everything in the rollout that can be scripted, in the order the setup guide
# gives (PABBLY_GENERATELINK_AUTH_SETUP.md §10).
#
#   scripts/auth-email/deploy.sh --project-ref <ref> [--env-file .env] [--dry-run]
#
# Reads the seven server-side values from your local env file (see the setup
# guide, section 3) and never prints them.
#
# Prerequisite you must do yourself, because it needs credentials:
#   npx supabase login             (opens a browser; stores an access token)
#
# What this does NOT do, deliberately:
#   * apply the migration      — paste supabase/200_auth_email_delivery.sql into
#                                the SQL editor, so you see its verification block
#   * add the redirect URL     — a production Auth setting; do it in the dashboard
#   * deploy the frontend      — last, and only after the checks in §11 pass
set -euo pipefail

PROJECT_REF=""; DRY_RUN=0; ENV_FILE=".env"

while [ $# -gt 0 ]; do
  case "$1" in
    --project-ref) PROJECT_REF="$2"; shift 2 ;;
    --env-file)    ENV_FILE="$2"; shift 2 ;;
    --dry-run)     DRY_RUN=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "$PROJECT_REF" ] || { echo "--project-ref is required (Supabase dashboard: Project Settings > General)" >&2; exit 2; }
[ -f "$ENV_FILE" ]    || { echo "No $ENV_FILE. It must hold the values listed in the setup guide, section 3." >&2; exit 2; }

SUPA="npx --yes supabase@latest"

# The values come from your local env file rather than being generated here: the
# shared secret must match the "Equal to" value already set in the Pabbly filter
# step, and rotating a working secret would silently break sending until both
# sides were changed together.
REQUIRED="PUBLIC_APP_URL PABBLY_AUTH_EMAIL_WEBHOOK_URL PABBLY_AUTH_EMAIL_SHARED_SECRET \
AUTH_EMAIL_FROM_ADDRESS AUTH_EMAIL_FROM_NAME AUTH_EMAIL_REPLY_TO AUTH_EMAIL_RATE_LIMIT_HASH_SECRET"

SECRETS_FILE="$(mktemp -t energia-auth-email-secrets)"
chmod 600 "$SECRETS_FILE"
trap 'rm -f "$SECRETS_FILE"' EXIT

# Optional values: copied through when present, silently skipped when not.
OPTIONAL="AUTH_EMAIL_TEST_ORIGINS AUTH_EMAIL_TEST_CALLBACK_URLS AUTH_EMAIL_TRUSTED_PROXY_HOPS AUTH_EMAIL_PABBLY_TIMEOUT_MS"

MISSING=""
for name in $REQUIRED; do
  line="$(grep -E "^${name}=" "$ENV_FILE" | tail -1 || true)"
  if [ -z "$line" ]; then MISSING="$MISSING $name"; else echo "$line" >> "$SECRETS_FILE"; fi
done
[ -z "$MISSING" ] || { echo "Missing from $ENV_FILE:$MISSING" >&2; exit 2; }

for name in $OPTIONAL; do
  line="$(grep -E "^${name}=" "$ENV_FILE" | tail -1 || true)"
  [ -z "$line" ] || echo "$line" >> "$SECRETS_FILE"
done

WEBHOOK="$(grep -E '^PABBLY_AUTH_EMAIL_WEBHOOK_URL=' "$ENV_FILE" | tail -1 | cut -d= -f2-)"
case "$WEBHOOK" in
  https://connect.pabbly.com/*) ;;
  *) echo "Refusing: PABBLY_AUTH_EMAIL_WEBHOOK_URL is not a Pabbly Connect webhook URL." >&2; exit 2 ;;
esac

echo "Read $(wc -l < "$SECRETS_FILE" | tr -d ' ') server-side values from $ENV_FILE (nothing printed)."
echo "SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY and SUPABASE_ANON_KEY are injected by the platform."
echo

if [ "$DRY_RUN" = "1" ]; then
  echo "--dry-run: stopping before anything is sent to Supabase."
  echo "Would run:"
  echo "  $SUPA secrets set --project-ref $PROJECT_REF --env-file <a temp copy of the 7 values>"
  for fn in auth-signup-request auth-resend-verification auth-request-recovery; do
    echo "  $SUPA functions deploy $fn --project-ref $PROJECT_REF --no-verify-jwt"
  done
  echo "  $SUPA functions deploy auth-change-password --project-ref $PROJECT_REF"
  exit 0
fi

echo "Setting secrets…"
$SUPA secrets set --project-ref "$PROJECT_REF" --env-file "$SECRETS_FILE"

# The three public endpoints must skip gateway JWT verification: nobody signing
# up or recovering a password has a session yet. auth-change-password keeps it.
for fn in auth-signup-request auth-resend-verification auth-request-recovery; do
  echo "Deploying $fn (no gateway JWT — public endpoint)…"
  $SUPA functions deploy "$fn" --project-ref "$PROJECT_REF" --no-verify-jwt
done
echo "Deploying auth-change-password (gateway JWT kept — requires a session)…"
$SUPA functions deploy auth-change-password --project-ref "$PROJECT_REF"

cat <<'NEXT'

Deployed. Still to do by hand, in this order:

  1. Apply supabase/200_auth_email_delivery.sql in the SQL editor, if you have
     not already. The functions fail closed until the rate-limit tables exist.
  2. Authentication → URL Configuration → Redirect URLs, add:
       .../affiliate/verify           (probably already there)
       .../affiliate/reset-password   (probably already there)
       .../reset-password             (new — staff recovery)
  3. Run the post-deploy checks:
       node scripts/auth-email/verify-deployed.mjs --url <project url> --anon-key <publishable key>
  4. Only then deploy the frontend.
NEXT

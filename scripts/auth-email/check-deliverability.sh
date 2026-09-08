#!/bin/sh
# Does the sending domain publish what receivers need in order to trust it?
#
#   scripts/auth-email/check-deliverability.sh [domain]
#
# Outlook junking your mail and Yahoo dropping it silently is almost always this,
# not the message content. Re-run after each DNS change; records take minutes to
# hours to propagate.
set -eu

D="${1:-rev22.com.sg}"
FAIL=0
say() { printf '%s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; FAIL=$((FAIL+1)); }
good() { printf '  ok    %s\n' "$*"; }

say "Checking $D"
say ""

say "MX — who accepts mail for the domain"
MX="$(dig +short MX "$D" | sort -n | head -1)"
if [ -z "$MX" ]; then bad "no MX record"; else
  good "$MX"
  case "$MX" in *aspmx.l.google.com*) say "        (Google Workspace)";; esac
fi
say ""

say "SPF — which servers may send as the domain"
SPF="$(dig +short TXT "$D" | tr -d '"' | grep -i '^v=spf1' || true)"
if [ -z "$SPF" ]; then
  bad "no SPF record"
  say "        add a TXT record on $D:"
  say "          v=spf1 include:_spf.google.com ~all"
else
  good "$SPF"
  case "$SPF" in *_spf.google.com*) ;; *) bad "SPF does not include _spf.google.com";; esac
fi
say ""

say "DKIM — is mail signed as this domain"
DKIM="$(dig +short TXT google._domainkey."$D" | tr -d '"' | head -1)"
if [ -z "$DKIM" ]; then
  bad "no google._domainkey record"
  say "        Google Admin > Apps > Google Workspace > Gmail > Authenticate email"
  say "        Generate the key, then publish the TXT record it gives you."
else
  good "google._domainkey present (${#DKIM} chars)"
fi
say ""

say "DMARC — what receivers should do when the above fail"
DMARC="$(dig +short TXT _dmarc."$D" | tr -d '"' | grep -i '^v=DMARC1' || true)"
if [ -z "$DMARC" ]; then
  bad "no DMARC record"
  say "        add a TXT record on _dmarc.$D:"
  say "          v=DMARC1; p=none; rua=mailto:info@$D; fo=1"
  say "        Start at p=none, read the reports for a fortnight, then tighten."
else
  good "$DMARC"
  case "$DMARC" in *p=none*) say "        (monitoring only — tighten to quarantine once reports look clean)";; esac
fi
say ""

if [ "$FAIL" -eq 0 ]; then
  say "All present. Send a test to a Gmail address and open Show original:"
  say "  SPF, DKIM and DMARC should each read PASS, and the DKIM domain must be $D."
  say "  A DKIM signed by gmail.com instead means the mail is still being sent by a"
  say "  personal Gmail account rather than the $D mailbox itself."
else
  say "$FAIL problem(s). Until these are fixed, expect junk folders and silent drops."
fi

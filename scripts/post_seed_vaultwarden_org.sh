#!/usr/bin/env bash
set -euo pipefail

# Companion for seed_admin_accounts.sh
# Vaultwarden-specific onboarding helper.
#
# Why a helper and not full automation?
# Vaultwarden organization membership/ownership uses client-side crypto flows,
# so safe org-owner setup is done through the web vault UI.
#
# This script:
# - validates env and service state
# - optionally enables/disables SIGNUPS_ALLOWED in .env + restarts vaultwarden
# - prints exact UI steps to finish org-owner setup for a seeded user
#
# Usage examples:
#   scripts/post_seed_vaultwarden_org.sh \
#     --email admin@example.com \
#     --org "Support Team"
#
#   scripts/post_seed_vaultwarden_org.sh \
#     --email admin@example.com \
#     --org "Support Team" \
#     --enable-signups
#
#   scripts/post_seed_vaultwarden_org.sh --disable-signups

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f .env ]]; then
  echo "Missing .env in $ROOT_DIR"
  exit 1
fi

EMAIL=""
ORG_NAME="Support Team"
ENABLE_SIGNUPS=false
DISABLE_SIGNUPS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --email) EMAIL="${2:-}"; shift 2 ;;
    --org) ORG_NAME="${2:-}"; shift 2 ;;
    --enable-signups) ENABLE_SIGNUPS=true; shift ;;
    --disable-signups) DISABLE_SIGNUPS=true; shift ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

set -a
# shellcheck disable=SC1091
source .env
set +a

if [[ -z "${VAULTWARDEN_DOMAIN:-}" ]]; then
  echo "Missing VAULTWARDEN_DOMAIN in .env"
  exit 1
fi

if [[ "$ENABLE_SIGNUPS" == true && "$DISABLE_SIGNUPS" == true ]]; then
  echo "Use either --enable-signups or --disable-signups, not both."
  exit 1
fi

update_signups() {
  local value="$1"
  if rg -q '^VAULTWARDEN_SIGNUPS_ALLOWED=' .env; then
    sed -i "s/^VAULTWARDEN_SIGNUPS_ALLOWED=.*/VAULTWARDEN_SIGNUPS_ALLOWED=${value}/" .env
  else
    printf "\nVAULTWARDEN_SIGNUPS_ALLOWED=%s\n" "$value" >> .env
  fi
  docker compose up -d vaultwarden >/dev/null
  echo "Updated VAULTWARDEN_SIGNUPS_ALLOWED=${value} and restarted vaultwarden."
}

if [[ "$ENABLE_SIGNUPS" == true ]]; then
  update_signups "true"
fi

if [[ "$DISABLE_SIGNUPS" == true ]]; then
  update_signups "false"
fi

echo
echo "Vaultwarden onboarding checklist"
echo "================================"
echo "Vault URL: ${VAULTWARDEN_DOMAIN}"
echo
if [[ -n "$EMAIL" ]]; then
  echo "Target user: ${EMAIL}"
fi
echo "Target organization: ${ORG_NAME}"
echo
echo "1) Register/login user in Vaultwarden"
echo "   - Go to: ${VAULTWARDEN_DOMAIN}"
if [[ "${VAULTWARDEN_SIGNUPS_ALLOWED:-false}" != "true" && "$ENABLE_SIGNUPS" != true ]]; then
  echo "   - NOTE: Signups are currently disabled in .env."
  echo "     Run this script with --enable-signups for initial registration."
fi
echo
echo "2) Create organization in web vault"
echo "   - Open Organizations -> New Organization"
echo "   - Name: ${ORG_NAME}"
echo "   - Complete setup wizard"
echo
echo "3) Make user owner/admin of that organization"
if [[ -n "$EMAIL" ]]; then
  echo "   - Invite ${EMAIL} (if not already owner by creator account)"
fi
echo "   - In Organization -> Members, set role to Owner"
echo
echo "4) Harden after first setup"
echo "   - Disable signups again:"
echo "     scripts/post_seed_vaultwarden_org.sh --disable-signups"
echo
echo "5) Global instance admin reminder"
echo "   - Vaultwarden instance admin remains /admin protected by ADMIN_TOKEN."
echo "   - This is separate from organization owner/admin roles."
echo
echo "Done."

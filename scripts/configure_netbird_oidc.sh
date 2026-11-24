#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${1:-.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 1
fi

env_get() {
  local key="$1" default="${2:-}" value
  value="$(grep -E "^${key}=" "$ENV_FILE" | head -n1 | cut -d= -f2- || true)"
  value="${value%\"}"
  value="${value#\"}"
  printf '%s' "${value:-$default}"
}

HOST="$(env_get NETBIRD_HOST)"
SSO_HOST="$(env_get SSO_HOST)"
REALM="$(env_get KEYCLOAK_REALM support)"
CLIENT_ID="$(env_get NETBIRD_OIDC_CLIENT_ID netbird)"
CLIENT_SECRET="$(env_get NETBIRD_OIDC_CLIENT_SECRET)"
API_TOKEN="$(env_get PROVISIONING_NETBIRD_API_TOKEN)"
RESOLVE_IP="$(env_get NETBIRD_BOOTSTRAP_RESOLVE_IP 127.0.0.1)"
PROVIDER_NAME="$(env_get PROVISIONING_NETBIRD_IDP_NAME Keycloak)"
ALLOW_GROUP="$(env_get PROVISIONING_NETBIRD_JWT_ALLOW_GROUP app-netbird)"
REQUIRE_APPROVAL="$(env_get PROVISIONING_NETBIRD_REQUIRE_USER_APPROVAL true)"

if [[ -z "$HOST" || -z "$SSO_HOST" || -z "$CLIENT_SECRET" || -z "$API_TOKEN" ]]; then
  echo "NETBIRD_HOST, SSO_HOST, NETBIRD_OIDC_CLIENT_SECRET and PROVISIONING_NETBIRD_API_TOKEN are required" >&2
  exit 1
fi
if [[ "$CLIENT_SECRET" == replace-with-* || "$API_TOKEN" == replace-with-* ]]; then
  echo "NetBird OIDC client secret and provisioning PAT must be real credentials" >&2
  exit 1
fi
case "${REQUIRE_APPROVAL,,}" in
  true|1|yes) REQUIRE_APPROVAL_JSON=true ;;
  false|0|no) REQUIRE_APPROVAL_JSON=false ;;
  *) echo "PROVISIONING_NETBIRD_REQUIRE_USER_APPROVAL must be true or false" >&2; exit 1 ;;
esac

BASE_URL="https://${HOST}"
ISSUER="https://${SSO_HOST}/realms/${REALM}"
CURL=(curl --fail-with-body --silent --show-error --resolve "${HOST}:443:${RESOLVE_IP}")

api() {
  local method="$1" path="$2"
  shift 2
  "${CURL[@]}" --request "$method" "$BASE_URL$path" \
    -H "Authorization: Token $API_TOKEN" "$@"
}

providers="$(api GET /api/identity-providers -H 'Accept: application/json')"
provider_matches="$(printf '%s' "$providers" | jq -c --arg client "$CLIENT_ID" \
  '[.[] | select(.client_id == $client)]')"
provider_count="$(printf '%s' "$provider_matches" | jq 'length')"
if (( provider_count > 1 )); then
  echo "Multiple NetBird identity providers use client ID '$CLIENT_ID'; refusing to choose" >&2
  exit 1
fi

provider_payload="$(jq -cn \
  --arg name "$PROVIDER_NAME" --arg issuer "$ISSUER" \
  --arg client "$CLIENT_ID" --arg secret "$CLIENT_SECRET" \
  '{type:"oidc",name:$name,issuer:$issuer,client_id:$client,client_secret:$secret}')"
if (( provider_count == 0 )); then
  echo "Creating NetBird Keycloak identity provider"
  api POST /api/identity-providers -H 'Content-Type: application/json' \
    --data "$provider_payload" >/dev/null
else
  provider_id="$(printf '%s' "$provider_matches" | jq -er '.[0].id')"
  echo "Updating NetBird Keycloak identity provider"
  api PUT "/api/identity-providers/${provider_id}" -H 'Content-Type: application/json' \
    --data "$provider_payload" >/dev/null
fi

accounts="$(api GET /api/accounts -H 'Accept: application/json')"
if [[ "$(printf '%s' "$accounts" | jq 'length')" != "1" ]]; then
  echo "Expected exactly one NetBird account" >&2
  exit 1
fi
account_id="$(printf '%s' "$accounts" | jq -er '.[0].id')"
account_payload="$(printf '%s' "$accounts" | jq -c --arg group "$ALLOW_GROUP" --argjson requireApproval "$REQUIRE_APPROVAL_JSON" '
  .[0] |
  {
    settings: (.settings + {
      jwt_groups_enabled: true,
      jwt_groups_claim_name: "groups",
      jwt_allow_groups: [$group],
      extra: ((.settings.extra // {}) + {user_approval_required: $requireApproval})
    }),
    onboarding: .onboarding
  }
')"
api PUT "/api/accounts/${account_id}" -H 'Content-Type: application/json' \
  --data "$account_payload" >/dev/null

verified_providers="$(api GET /api/identity-providers -H 'Accept: application/json')"
verified_accounts="$(api GET /api/accounts -H 'Accept: application/json')"
printf '%s' "$verified_providers" | jq -e --arg issuer "$ISSUER" --arg client "$CLIENT_ID" \
  'any(.[]; .issuer == $issuer and .client_id == $client)' >/dev/null
printf '%s' "$verified_accounts" | jq -e --arg group "$ALLOW_GROUP" \
  '.[0].settings | .jwt_groups_enabled == true and .jwt_groups_claim_name == "groups" and .jwt_allow_groups == [$group]' >/dev/null

echo "NetBird OIDC and JWT group synchronization are configured."
echo "Allowed JWT group: $ALLOW_GROUP"
echo "Administrator approval required for new users: $REQUIRE_APPROVAL_JSON"

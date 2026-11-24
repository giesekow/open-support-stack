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

env_set() {
  local key="$1" value="$2" temporary
  temporary="$(mktemp "${ENV_FILE}.tmp.XXXXXX")"
  awk -v key="$key" -v value="$value" '
    BEGIN { updated = 0 }
    $0 ~ "^" key "=" {
      if (!updated) print key "=" value
      updated = 1
      next
    }
    { print }
    END { if (!updated) print key "=" value }
  ' "$ENV_FILE" >"$temporary"
  chmod --reference="$ENV_FILE" "$temporary"
  mv "$temporary" "$ENV_FILE"
}

HOST="$(env_get NETBIRD_HOST)"
ADMIN_EMAIL="$(env_get NETBIRD_ADMIN_EMAIL)"
ADMIN_PASSWORD="$(env_get NETBIRD_ADMIN_PASSWORD)"
RESOLVE_IP="$(env_get NETBIRD_BOOTSTRAP_RESOLVE_IP 127.0.0.1)"
SERVICE_NAME="$(env_get PROVISIONING_NETBIRD_SERVICE_USER support-tools-provisioning)"
TOKEN_NAME="$(env_get PROVISIONING_NETBIRD_TOKEN_NAME support-tools-provisioning)"
TOKEN_DAYS="$(env_get PROVISIONING_NETBIRD_TOKEN_DAYS 365)"
CONFIGURED_TOKEN="$(env_get PROVISIONING_NETBIRD_API_TOKEN)"

if [[ -z "$HOST" || -z "$ADMIN_EMAIL" || -z "$ADMIN_PASSWORD" ]]; then
  echo "NETBIRD_HOST, NETBIRD_ADMIN_EMAIL and NETBIRD_ADMIN_PASSWORD are required" >&2
  exit 1
fi
if ! [[ "$TOKEN_DAYS" =~ ^[0-9]+$ ]] || (( TOKEN_DAYS < 1 || TOKEN_DAYS > 365 )); then
  echo "PROVISIONING_NETBIRD_TOKEN_DAYS must be between 1 and 365" >&2
  exit 1
fi

BASE_URL="https://${HOST}"
CURL=(curl --silent --show-error --resolve "${HOST}:443:${RESOLVE_IP}")

if [[ -n "$CONFIGURED_TOKEN" && "$CONFIGURED_TOKEN" != replace-with-* ]]; then
  if "${CURL[@]}" --fail-with-body "$BASE_URL/api/users" \
    -H "Authorization: Token $CONFIGURED_TOKEN" >/dev/null 2>&1; then
    echo "NetBird provisioning PAT is already valid; no rotation performed."
    exit 0
  fi
fi

verifier="$(openssl rand -base64 48 | tr '+/' '-_' | tr -d '=\n')"
challenge="$(printf '%s' "$verifier" | openssl dgst -sha256 -binary | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
state="$(openssl rand -hex 16)"
nonce="$(openssl rand -hex 16)"
cookie_jar="$(mktemp /tmp/netbird-bootstrap-cookie.XXXXXX)"
login_html="$(mktemp /tmp/netbird-bootstrap-login.XXXXXX)"
trap 'rm -f "$cookie_jar" "$login_html"' EXIT

auth_url="$BASE_URL/oauth2/auth?client_id=netbird-dashboard&redirect_uri=https%3A%2F%2F${HOST}%2Fnb-auth&response_type=code&scope=openid%20profile%20email%20groups&state=${state}&nonce=${nonce}&code_challenge=${challenge}&code_challenge_method=S256"
login_url="$("${CURL[@]}" --location --cookie-jar "$cookie_jar" \
  --output "$login_html" --write-out '%{url_effective}' "$auth_url")"
callback_url="$("${CURL[@]}" --location --cookie "$cookie_jar" --cookie-jar "$cookie_jar" \
  --output /dev/null --write-out '%{url_effective}' \
  --data-urlencode "login=$ADMIN_EMAIL" --data-urlencode "password=$ADMIN_PASSWORD" \
  "$login_url")"
code="$(printf '%s' "$callback_url" | sed -n 's/.*[?&]code=\([^&]*\).*/\1/p')"
returned_state="$(printf '%s' "$callback_url" | sed -n 's/.*[?&]state=\([^&]*\).*/\1/p')"
if [[ -z "$code" || "$returned_state" != "$state" ]]; then
  echo "NetBird owner OAuth login failed" >&2
  exit 1
fi

owner_token="$("${CURL[@]}" --fail-with-body --request POST "$BASE_URL/oauth2/token" \
  --data-urlencode grant_type=authorization_code \
  --data-urlencode client_id=netbird-dashboard \
  --data-urlencode "redirect_uri=$BASE_URL/nb-auth" \
  --data-urlencode "code=$code" \
  --data-urlencode "code_verifier=$verifier" | jq -er .access_token)"

api() {
  local method="$1" path="$2"
  shift 2
  "${CURL[@]}" --fail-with-body --request "$method" "$BASE_URL$path" \
    -H "Authorization: Bearer $owner_token" "$@"
}

users="$(api GET /api/users -H 'Accept: application/json')"
service_id="$(printf '%s' "$users" | jq -r --arg name "$SERVICE_NAME" \
  '[.[] | select(.is_service_user == true and .name == $name)] | if length == 1 then .[0].id elif length == 0 then "" else error("multiple matching service users") end')"
if [[ -z "$service_id" ]]; then
  echo "Creating NetBird service user '$SERVICE_NAME'"
  service_id="$(api POST /api/users \
    -H 'Accept: application/json' -H 'Content-Type: application/json' \
    --data "$(jq -cn --arg name "$SERVICE_NAME" '{name:$name,role:"admin",auto_groups:[],is_service_user:true}')" \
    | jq -er .id)"
fi

tokens="$(api GET "/api/users/${service_id}/tokens" -H 'Accept: application/json')"
while IFS= read -r token_id; do
  [[ -z "$token_id" ]] || api DELETE "/api/users/${service_id}/tokens/${token_id}" >/dev/null
done < <(printf '%s' "$tokens" | jq -r --arg name "$TOKEN_NAME" '.[]? | select(.name == $name) | .id')

created="$(api POST "/api/users/${service_id}/tokens" \
  -H 'Accept: application/json' -H 'Content-Type: application/json' \
  --data "$(jq -cn --arg name "$TOKEN_NAME" --argjson days "$TOKEN_DAYS" '{name:$name,expires_in:$days}')")"
plain_token="$(printf '%s' "$created" | jq -er '.plain_token | if type == "string" then . else .token // .value // empty end')"
if [[ -z "$plain_token" ]]; then
  echo "NetBird did not return a plain token" >&2
  exit 1
fi

env_set PROVISIONING_NETBIRD_API_TOKEN "$plain_token"
echo "Created NetBird service-user PAT and stored it in $ENV_FILE."
echo "Recreate support-tools to load it: docker compose --env-file $ENV_FILE up -d --force-recreate support-tools"

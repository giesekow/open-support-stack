#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${1:-.env}"
CONFIG_TEMPLATE="config/netbird/config.template.yaml"
CONFIG_OUT="config/netbird/config.yaml"
DASHBOARD_TEMPLATE="config/netbird/dashboard.env.template"
DASHBOARD_OUT="config/netbird/dashboard.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[FAIL] Missing env file: $ENV_FILE"
  exit 1
fi

env_get() {
  local key="$1"
  local def="$2"
  local val
  val="$(awk -F= -v k="$key" '$1==k {sub(/^[^=]*=/, "", $0); print; exit}' "$ENV_FILE" | tr -d '\r')"
  printf '%s' "${val:-$def}"
}

require_safe_value() {
  local key="$1"
  local value="$2"
  if [[ -z "$value" || "$value" == *'"'* || "$value" == *$'\n'* ]]; then
    echo "[FAIL] $key is empty or contains characters unsafe for generated YAML"
    exit 1
  fi
}

decoded_base64_size() {
  local value="$1"
  printf '%s' "$value" | base64 --decode 2>/dev/null | wc -c | tr -d ' '
}

require_aes_key() {
  local key="$1"
  local value="$2"
  local raw_size="${#value}"
  local decoded_size=""

  if [[ "$raw_size" == "16" || "$raw_size" == "24" || "$raw_size" == "32" ]]; then
    return
  fi
  if ! decoded_size="$(decoded_base64_size "$value")"; then
    decoded_size=""
  fi
  if [[ "$decoded_size" == "16" || "$decoded_size" == "24" || "$decoded_size" == "32" ]]; then
    return
  fi

  echo "[FAIL] $key must contain 16, 24, or 32 raw bytes, or their base64 encoding"
  exit 1
}

require_base64_bytes() {
  local key="$1"
  local value="$2"
  local expected="$3"
  local decoded_size
  if ! decoded_size="$(decoded_base64_size "$value")"; then
    decoded_size=""
  fi
  if [[ "$decoded_size" != "$expected" ]]; then
    echo "[FAIL] $key must be valid base64 encoding exactly $expected bytes"
    exit 1
  fi
}

replace() {
  local file="$1"
  local placeholder="$2"
  local value="$3"
  local escaped
  escaped="$(printf '%s' "$value" | sed -e 's/[|&\\]/\\&/g')"
  sed -i "s|${placeholder}|${escaped}|g" "$file"
}

BASE_DOMAIN="$(env_get BASE_DOMAIN example.com)"
NETBIRD_HOST="$(env_get NETBIRD_HOST "netbird.${BASE_DOMAIN}")"
NETBIRD_RELAY_AUTH_SECRET="$(env_get NETBIRD_RELAY_AUTH_SECRET '')"
NETBIRD_SESSION_COOKIE_KEY="$(env_get NETBIRD_SESSION_COOKIE_KEY '')"
NETBIRD_DATASTORE_ENCRYPTION_KEY="$(env_get NETBIRD_DATASTORE_ENCRYPTION_KEY '')"
NETBIRD_ADMIN_EMAIL="$(env_get NETBIRD_ADMIN_EMAIL "admin@${BASE_DOMAIN}")"
NETBIRD_ADMIN_PASSWORD="$(env_get NETBIRD_ADMIN_PASSWORD '')"
NETBIRD_ADMIN_PASSWORD_HASH_B64="$(env_get NETBIRD_ADMIN_PASSWORD_HASH_B64 '')"
NETBIRD_TRUSTED_PROXY_CIDR="$(env_get NETBIRD_TRUSTED_PROXY_CIDR '172.16.0.0/12')"
NETBIRD_DISABLE_ANONYMOUS_METRICS="$(env_get NETBIRD_DISABLE_ANONYMOUS_METRICS 'true')"

for key in NETBIRD_HOST NETBIRD_RELAY_AUTH_SECRET NETBIRD_SESSION_COOKIE_KEY \
  NETBIRD_DATASTORE_ENCRYPTION_KEY NETBIRD_ADMIN_EMAIL NETBIRD_ADMIN_PASSWORD \
  NETBIRD_ADMIN_PASSWORD_HASH_B64 \
  NETBIRD_TRUSTED_PROXY_CIDR; do
  require_safe_value "$key" "${!key}"
done

require_aes_key NETBIRD_SESSION_COOKIE_KEY "$NETBIRD_SESSION_COOKIE_KEY"
require_base64_bytes NETBIRD_DATASTORE_ENCRYPTION_KEY "$NETBIRD_DATASTORE_ENCRYPTION_KEY" 32

if [[ "${#NETBIRD_RELAY_AUTH_SECRET}" -lt 32 ]]; then
  echo "[FAIL] NETBIRD_RELAY_AUTH_SECRET must be at least 32 characters"
  exit 1
fi
if [[ "${#NETBIRD_ADMIN_PASSWORD}" -lt 16 ]]; then
  echo "[FAIL] NETBIRD_ADMIN_PASSWORD must be at least 16 characters"
  exit 1
fi
if ! NETBIRD_ADMIN_PASSWORD_HASH="$(printf '%s' "$NETBIRD_ADMIN_PASSWORD_HASH_B64" | base64 --decode 2>/dev/null)"; then
  echo "[FAIL] NETBIRD_ADMIN_PASSWORD_HASH_B64 must be valid base64"
  exit 1
fi
if [[ ! "$NETBIRD_ADMIN_PASSWORD_HASH" =~ ^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$ ]]; then
  echo "[FAIL] NETBIRD_ADMIN_PASSWORD_HASH_B64 must decode to a bcrypt hash"
  exit 1
fi
if [[ "$NETBIRD_ADMIN_EMAIL" != *@* ]]; then
  echo "[FAIL] NETBIRD_ADMIN_EMAIL must be an email address"
  exit 1
fi
if [[ ! "$NETBIRD_HOST" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "[FAIL] NETBIRD_HOST must be a hostname without a scheme or path"
  exit 1
fi
if [[ "$NETBIRD_DISABLE_ANONYMOUS_METRICS" != "true" && "$NETBIRD_DISABLE_ANONYMOUS_METRICS" != "false" ]]; then
  echo "[FAIL] NETBIRD_DISABLE_ANONYMOUS_METRICS must be true or false"
  exit 1
fi

mkdir -p "$(dirname "$CONFIG_OUT")"
config_tmp="$(mktemp)"
dashboard_tmp="$(mktemp)"
trap 'rm -f "$config_tmp" "$dashboard_tmp"' EXIT
cp "$CONFIG_TEMPLATE" "$config_tmp"
cp "$DASHBOARD_TEMPLATE" "$dashboard_tmp"

replace "$config_tmp" __NETBIRD_HOST__ "$NETBIRD_HOST"
replace "$config_tmp" __NETBIRD_RELAY_AUTH_SECRET__ "$NETBIRD_RELAY_AUTH_SECRET"
replace "$config_tmp" __NETBIRD_SESSION_COOKIE_KEY__ "$NETBIRD_SESSION_COOKIE_KEY"
replace "$config_tmp" __NETBIRD_DATASTORE_ENCRYPTION_KEY__ "$NETBIRD_DATASTORE_ENCRYPTION_KEY"
replace "$config_tmp" __NETBIRD_ADMIN_EMAIL__ "$NETBIRD_ADMIN_EMAIL"
replace "$config_tmp" __NETBIRD_ADMIN_PASSWORD_HASH__ "$NETBIRD_ADMIN_PASSWORD_HASH"
replace "$config_tmp" __NETBIRD_TRUSTED_PROXY_CIDR__ "$NETBIRD_TRUSTED_PROXY_CIDR"
replace "$config_tmp" __NETBIRD_DISABLE_ANONYMOUS_METRICS__ "$NETBIRD_DISABLE_ANONYMOUS_METRICS"
replace "$dashboard_tmp" __NETBIRD_HOST__ "$NETBIRD_HOST"

if grep -Eq '__[A-Z0-9_]+__' "$config_tmp" "$dashboard_tmp"; then
  echo "[FAIL] Unresolved NetBird template placeholders remain"
  exit 1
fi

install -m 600 "$config_tmp" "$CONFIG_OUT"
install -m 600 "$dashboard_tmp" "$DASHBOARD_OUT"
echo "[OK] Rendered $CONFIG_OUT and $DASHBOARD_OUT from $ENV_FILE"

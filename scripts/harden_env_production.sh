#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${1:-.env.production}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE"
  exit 1
fi

tmp="$(mktemp)"
cp "$ENV_FILE" "$tmp"

set_kv() {
  local key="$1"
  local val="$2"
  if rg -q "^${key}=" "$tmp"; then
    sed -i "s|^${key}=.*|${key}=${val}|" "$tmp"
  else
    printf "%s=%s\n" "$key" "$val" >> "$tmp"
  fi
}

rand_hex() {
  local bytes="$1"
  openssl rand -hex "$bytes"
}

rand_b64_44() {
  # 32-byte key for BookStack APP_KEY
  openssl rand -base64 32
}

set_kv "KEYCLOAK_DB_PASSWORD" "$(rand_hex 24)"
set_kv "KEYCLOAK_ADMIN_PASSWORD" "$(rand_hex 24)"
set_kv "BOOKSTACK_DB_ROOT_PASSWORD" "$(rand_hex 24)"
set_kv "BOOKSTACK_DB_PASSWORD" "$(rand_hex 24)"
set_kv "BOOKSTACK_APP_KEY" "base64:$(rand_b64_44)"
set_kv "GUACAMOLE_DB_PASSWORD" "$(rand_hex 24)"
set_kv "OSTICKET_DB_PASSWORD" "$(rand_hex 24)"
set_kv "OSTICKET_DB_ROOT_PASSWORD" "$(rand_hex 24)"
set_kv "OSTICKET_INSTALL_SECRET" "$(rand_hex 32)"
set_kv "OSTICKET_ADMIN_PASSWORD" "$(rand_hex 24)"
set_kv "ESPOCRM_DB_PASSWORD" "$(rand_hex 24)"
set_kv "ESPOCRM_DB_ROOT_PASSWORD" "$(rand_hex 24)"
set_kv "ESPOCRM_ADMIN_PASSWORD" "$(rand_hex 24)"
set_kv "SUPPORT_PORTAL_OIDC_COOKIE_SECRET" "$(rand_hex 16)"

mv "$tmp" "$ENV_FILE"
echo "Updated secure secrets in $ENV_FILE"

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

bcrypt_b64() {
  local password="$1"
  if ! python3 -c 'import bcrypt' 2>/dev/null; then
    echo "python3 bcrypt is required to generate NETBIRD_ADMIN_PASSWORD_HASH_B64" >&2
    exit 1
  fi
  NETBIRD_PASSWORD="$password" python3 -c 'import base64, bcrypt, os; print(base64.b64encode(bcrypt.hashpw(os.environ["NETBIRD_PASSWORD"].encode(), bcrypt.gensalt())).decode())'
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
set_kv "SUPPORT_TOOLS_DB_PASSWORD" "$(rand_hex 24)"
set_kv "SUPPORT_TOOLS_SESSION_SECRET" "$(rand_hex 32)"
set_kv "SUPPORT_TOOLS_COOKIE_SECURE" "true"
set_kv "SUPPORT_TOOLS_DEV_AUTH_BYPASS" "false"
set_kv "NETBIRD_RELAY_AUTH_SECRET" "$(rand_hex 32)"
set_kv "NETBIRD_SESSION_COOKIE_KEY" "$(rand_hex 16)"
set_kv "NETBIRD_DATASTORE_ENCRYPTION_KEY" "$(openssl rand -base64 32)"
netbird_admin_password="Nb!7$(rand_hex 22)"
set_kv "NETBIRD_ADMIN_PASSWORD" "$netbird_admin_password"
set_kv "NETBIRD_ADMIN_PASSWORD_HASH_B64" "$(bcrypt_b64 "$netbird_admin_password")"
set_kv "NETBIRD_OIDC_CLIENT_SECRET" "$(rand_hex 32)"

mv "$tmp" "$ENV_FILE"
echo "Updated secure secrets in $ENV_FILE"

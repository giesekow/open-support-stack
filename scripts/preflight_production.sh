#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE="${1:-.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[FAIL] Missing env file: $ENV_FILE"
  exit 1
fi

echo "==> Production preflight ($ENV_FILE)"

failures=0
warns=0

check_required() {
  local key="$1"
  local val
  val="$(grep -E "^${key}=" "$ENV_FILE" | head -n1 | cut -d= -f2- || true)"
  if [[ -z "$val" ]]; then
    echo "[FAIL] ${key} is missing or empty"
    failures=$((failures + 1))
  fi
}

check_not_placeholder() {
  local key="$1"
  local val
  val="$(grep -E "^${key}=" "$ENV_FILE" | head -n1 | cut -d= -f2- || true)"
  if [[ -z "$val" || "$val" == *"change-this"* || "$val" == *"replace-with"* ]]; then
    echo "[FAIL] ${key} still looks like a placeholder"
    failures=$((failures + 1))
  fi
}

check_equals() {
  local key="$1"
  local expected="$2"
  local val
  val="$(grep -E "^${key}=" "$ENV_FILE" | head -n1 | cut -d= -f2- || true)"
  if [[ "$val" != "$expected" ]]; then
    echo "[WARN] ${key} is '${val:-<unset>}' (expected '${expected}' for production)"
    warns=$((warns + 1))
  fi
}

for k in \
  KEYCLOAK_DB_PASSWORD \
  KEYCLOAK_ADMIN_PASSWORD \
  BOOKSTACK_DB_PASSWORD \
  BOOKSTACK_DB_ROOT_PASSWORD \
  GUACAMOLE_DB_PASSWORD \
  OSTICKET_DB_PASSWORD \
  OSTICKET_DB_ROOT_PASSWORD \
  OSTICKET_ADMIN_PASSWORD \
  ESPOCRM_DB_PASSWORD \
  ESPOCRM_DB_ROOT_PASSWORD \
  ESPOCRM_ADMIN_PASSWORD \
  OSTICKET_OIDC_CLIENT_SECRET \
  MESHWEB_OIDC_CLIENT_SECRET \
  MESHWEB_OIDC_COOKIE_SECRET \
  SUPPORT_PORTAL_OIDC_COOKIE_SECRET
do
  check_required "$k"
  check_not_placeholder "$k"
done

check_equals "KEYCLOAK_START_CMD" "start"
check_equals "KEYCLOAK_HOSTNAME_STRICT" "true"
check_equals "MESHWEB_OIDC_SSL_INSECURE_SKIP_VERIFY" "false"
check_equals "SUPPORT_PORTAL_OIDC_SSL_INSECURE_SKIP_VERIFY" "false"
check_equals "VAULTWARDEN_SIGNUPS_ALLOWED" "false"

if grep -q '^KEYCLOAK_ADMIN_PASSWORD=admin$' "$ENV_FILE"; then
  echo "[FAIL] KEYCLOAK_ADMIN_PASSWORD is still set to default 'admin'"
  failures=$((failures + 1))
fi

le_enabled="$(grep -E '^ENABLE_LETSENCRYPT=' "$ENV_FILE" | head -n1 | cut -d= -f2- || true)"
if [[ "$le_enabled" == "true" ]]; then
  check_required "LETSENCRYPT_EMAIL"
  check_required "LETSENCRYPT_DOMAINS"
  check_required "LETSENCRYPT_PRIMARY_DOMAIN"
fi

if [[ -f nginx/certs/support-stack.crt ]]; then
  if openssl x509 -in nginx/certs/support-stack.crt -noout -subject >/dev/null 2>&1; then
    exp="$(openssl x509 -in nginx/certs/support-stack.crt -noout -enddate | cut -d= -f2-)"
    echo "[OK] TLS cert loaded (expires: ${exp})"
  else
    echo "[WARN] Could not parse nginx/certs/support-stack.crt"
    warns=$((warns + 1))
  fi
else
  echo "[WARN] Missing nginx/certs/support-stack.crt"
  warns=$((warns + 1))
fi

echo
if (( failures > 0 )); then
  echo "Preflight completed with ${failures} hard failure(s) and ${warns} warning(s)."
  exit 1
fi
echo "Preflight passed with ${warns} warning(s)."

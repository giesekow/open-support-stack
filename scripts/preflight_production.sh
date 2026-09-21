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

env_value() {
  local key="$1"
  grep -E "^${key}=" "$ENV_FILE" | head -n1 | cut -d= -f2- || true
}

check_required() {
  local key="$1"
  local val
  val="$(env_value "$key")"
  if [[ -z "$val" ]]; then
    echo "[FAIL] ${key} is missing or empty"
    failures=$((failures + 1))
  fi
}

check_not_placeholder() {
  local key="$1"
  local val
  val="$(env_value "$key")"
  if [[ -z "$val" || "$val" == *"change-this"* || "$val" == *"replace-with"* ]]; then
    echo "[FAIL] ${key} still looks like a placeholder"
    failures=$((failures + 1))
  fi
}

check_equals() {
  local key="$1"
  local expected="$2"
  local val
  val="$(env_value "$key")"
  if [[ "$val" != "$expected" ]]; then
    echo "[WARN] ${key} is '${val:-<unset>}' (expected '${expected}' for production)"
    warns=$((warns + 1))
  fi
}

check_min_length() {
  local key="$1"
  local minimum="$2"
  local val
  val="$(env_value "$key")"
  if [[ "${#val}" -lt "$minimum" ]]; then
    echo "[FAIL] ${key} must be at least ${minimum} characters"
    failures=$((failures + 1))
  fi
}

check_netbird_cookie_key() {
  local val raw_size decoded_size=""
  val="$(env_value NETBIRD_SESSION_COOKIE_KEY)"
  raw_size="${#val}"
  if [[ "$raw_size" == "16" || "$raw_size" == "24" || "$raw_size" == "32" ]]; then
    return
  fi
  if decoded_size="$(printf '%s' "$val" | base64 --decode 2>/dev/null | wc -c | tr -d ' ')" && \
     [[ "$decoded_size" == "16" || "$decoded_size" == "24" || "$decoded_size" == "32" ]]; then
    return
  fi
  echo "[FAIL] NETBIRD_SESSION_COOKIE_KEY is not a valid AES key length"
  failures=$((failures + 1))
}

check_base64_size() {
  local key="$1"
  local expected="$2"
  local val decoded_size=""
  val="$(env_value "$key")"
  if ! decoded_size="$(printf '%s' "$val" | base64 --decode 2>/dev/null | wc -c | tr -d ' ')" || \
     [[ "$decoded_size" != "$expected" ]]; then
    echo "[FAIL] ${key} must be valid base64 encoding exactly ${expected} bytes"
    failures=$((failures + 1))
  fi
}

check_bcrypt_b64() {
  local value decoded=""
  value="$(env_value NETBIRD_ADMIN_PASSWORD_HASH_B64)"
  if ! decoded="$(printf '%s' "$value" | base64 --decode 2>/dev/null)" || \
     [[ ! "$decoded" =~ ^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$ ]]; then
    echo "[FAIL] NETBIRD_ADMIN_PASSWORD_HASH_B64 must encode a bcrypt hash"
    failures=$((failures + 1))
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
  SUPPORT_PORTAL_OIDC_COOKIE_SECRET \
  NETBIRD_RELAY_AUTH_SECRET \
  NETBIRD_SESSION_COOKIE_KEY \
  NETBIRD_DATASTORE_ENCRYPTION_KEY \
  NETBIRD_ADMIN_PASSWORD \
  NETBIRD_ADMIN_PASSWORD_HASH_B64 \
  NETBIRD_OIDC_CLIENT_SECRET
do
  check_required "$k"
  check_not_placeholder "$k"
done

check_min_length "NETBIRD_RELAY_AUTH_SECRET" 32
check_min_length "NETBIRD_ADMIN_PASSWORD" 16
check_min_length "NETBIRD_OIDC_CLIENT_SECRET" 32
check_netbird_cookie_key
check_base64_size "NETBIRD_DATASTORE_ENCRYPTION_KEY" 32
check_bcrypt_b64

netbird_server_image="$(env_value NETBIRD_SERVER_IMAGE)"
netbird_dashboard_image="$(env_value NETBIRD_DASHBOARD_IMAGE)"
if [[ "$netbird_server_image" != *@sha256:* ]]; then
  echo "[FAIL] NETBIRD_SERVER_IMAGE must be pinned by sha256 digest"
  failures=$((failures + 1))
fi
if [[ "$netbird_dashboard_image" != *@sha256:* ]]; then
  echo "[FAIL] NETBIRD_DASHBOARD_IMAGE must be pinned by sha256 digest"
  failures=$((failures + 1))
fi

check_equals "KEYCLOAK_START_CMD" "start"
check_equals "KEYCLOAK_HOSTNAME_STRICT" "true"
check_equals "MESHWEB_OIDC_SSL_INSECURE_SKIP_VERIFY" "false"
check_equals "SUPPORT_PORTAL_OIDC_SSL_INSECURE_SKIP_VERIFY" "false"
check_equals "VAULTWARDEN_SIGNUPS_ALLOWED" "false"
check_equals "NETBIRD_DISABLE_ANONYMOUS_METRICS" "true"

netbird_host="$(env_value NETBIRD_HOST)"
netbird_stun_port="$(env_value NETBIRD_STUN_PORT)"
netbird_proxy_cidr="$(env_value NETBIRD_TRUSTED_PROXY_CIDR)"
nginx_proxy_cidr="$(env_value NGINX_TRUSTED_PROXY_CIDR)"
if [[ -z "$netbird_host" || ! "$netbird_host" =~ ^[A-Za-z0-9.-]+$ ]]; then
  echo "[FAIL] NETBIRD_HOST must be a hostname without a scheme or path"
  failures=$((failures + 1))
fi
if [[ ! "$netbird_stun_port" =~ ^[0-9]+$ ]] || \
   (( 10#$netbird_stun_port < 1 || 10#$netbird_stun_port > 65535 )); then
  echo "[FAIL] NETBIRD_STUN_PORT must be between 1 and 65535"
  failures=$((failures + 1))
fi
if [[ -z "$netbird_proxy_cidr" || "$netbird_proxy_cidr" == "0.0.0.0/0" || "$netbird_proxy_cidr" == "::/0" ]]; then
  echo "[FAIL] NETBIRD_TRUSTED_PROXY_CIDR must be a restricted network CIDR"
  failures=$((failures + 1))
fi
if [[ -z "$nginx_proxy_cidr" || "$nginx_proxy_cidr" == "0.0.0.0/0" || "$nginx_proxy_cidr" == "::/0" ]]; then
  echo "[FAIL] NGINX_TRUSTED_PROXY_CIDR must be a restricted network CIDR"
  failures=$((failures + 1))
fi

if grep -q '^KEYCLOAK_ADMIN_PASSWORD=admin$' "$ENV_FILE"; then
  echo "[FAIL] KEYCLOAK_ADMIN_PASSWORD is still set to default 'admin'"
  failures=$((failures + 1))
fi

le_enabled="$(grep -E '^ENABLE_LETSENCRYPT=' "$ENV_FILE" | head -n1 | cut -d= -f2- || true)"
if [[ "$le_enabled" == "true" ]]; then
  check_required "LETSENCRYPT_EMAIL"
  check_required "LETSENCRYPT_DOMAINS"
  check_required "LETSENCRYPT_PRIMARY_DOMAIN"
  letsencrypt_domains="$(env_value LETSENCRYPT_DOMAINS)"
  if ! printf '%s' "$letsencrypt_domains" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -Fxq "$netbird_host"; then
    echo "[FAIL] LETSENCRYPT_DOMAINS does not include NETBIRD_HOST (${netbird_host})"
    failures=$((failures + 1))
  fi
fi

nginx_mode="$(env_value NGINX_MODE)"
if [[ "$nginx_mode" != "https" ]]; then
  echo "[OK] Local TLS certificate check skipped (NGINX_MODE=${nginx_mode:-<unset>})"
elif [[ -f nginx/certs/support-stack.crt ]]; then
  if openssl x509 -in nginx/certs/support-stack.crt -noout -subject >/dev/null 2>&1; then
    exp="$(openssl x509 -in nginx/certs/support-stack.crt -noout -enddate | cut -d= -f2-)"
    echo "[OK] TLS cert loaded (expires: ${exp})"
    if [[ "$nginx_mode" == "https" && "$le_enabled" != "true" ]] && \
       ! openssl x509 -in nginx/certs/support-stack.crt -noout -checkhost "$netbird_host" >/dev/null 2>&1; then
      echo "[FAIL] nginx/certs/support-stack.crt does not cover NETBIRD_HOST (${netbird_host})"
      failures=$((failures + 1))
    fi
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

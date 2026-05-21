#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f .env ]]; then
  echo "[ERROR] Missing .env in $ROOT_DIR"
  exit 1
fi

read_env_value() {
  local key="$1"
  local value
  value="$(grep -E "^${key}=" .env | head -n 1 | cut -d '=' -f2- || true)"
  printf '%s' "$value"
}

OSTICKET_OIDC_ISSUER="$(read_env_value OSTICKET_OIDC_ISSUER)"
if [[ -z "$OSTICKET_OIDC_ISSUER" ]]; then
  echo "[ERROR] Missing OSTICKET_OIDC_ISSUER in .env"
  exit 1
fi

PLUGIN_DIR=""
if docker compose exec -T osticket sh -lc "test -d /var/www/html/include/plugins/auth-oauth2" >/dev/null 2>&1; then
  PLUGIN_DIR="/var/www/html/include/plugins/auth-oauth2"
elif docker compose exec -T osticket sh -lc "test -d /data/upload/include/plugins/auth-oauth2" >/dev/null 2>&1; then
  PLUGIN_DIR="/data/upload/include/plugins/auth-oauth2"
else
  PLUGIN_DIR="/var/www/html/include/plugins/auth-oauth2"
fi
DISCOVERY_URL="${OSTICKET_OIDC_ISSUER%/}/.well-known/openid-configuration"
AUTH_URL="${OSTICKET_OIDC_ISSUER%/}/protocol/openid-connect/auth"
TOKEN_URL="${OSTICKET_OIDC_ISSUER%/}/protocol/openid-connect/token"
USERINFO_URL="${OSTICKET_OIDC_ISSUER%/}/protocol/openid-connect/userinfo"

failures=0

check_plugin() {
  echo "[CHECK] osTicket OAuth2 plugin files"
  if docker compose exec -T osticket sh -lc "test -f '$PLUGIN_DIR/plugin.php' && test -f '$PLUGIN_DIR/auth.php'"; then
    echo "[OK] Plugin present at $PLUGIN_DIR"
  else
    echo "[FAIL] Plugin not found at $PLUGIN_DIR"
    failures=$((failures + 1))
  fi
}

check_url_from_osticket() {
  local url="$1"
  local label="$2"
  local status=""
  local status_insecure=""
  local attempt=1
  local max_attempts=8

  while [[ $attempt -le $max_attempts ]]; do
    status="$(
      docker compose exec -T osticket sh -lc \
        "wget -S -O /dev/null --spider '$url' 2>&1 | awk '/^  HTTP\\// {code=\$2} END {print code}'" \
        2>/dev/null || true
    )"
    if [[ -n "$status" && ! "$status" =~ ^5[0-9][0-9]$ ]]; then
      echo "[OK] $label reachable with TLS verification (HTTP $status): $url"
      return
    fi

    status_insecure="$(
      docker compose exec -T osticket sh -lc \
        "wget -S -O /dev/null --spider --no-check-certificate '$url' 2>&1 | awk '/^  HTTP\\// {code=\$2} END {print code}'" \
        2>/dev/null || true
    )"
    if [[ -n "$status_insecure" && ! "$status_insecure" =~ ^5[0-9][0-9]$ ]]; then
      echo "[WARN] $label reachable only with --no-check-certificate (HTTP $status_insecure): $url"
      echo "       Your self-signed cert is not trusted inside osticket container."
      return
    fi

    if [[ $attempt -lt $max_attempts ]]; then
      sleep 2
    fi
    attempt=$((attempt + 1))
  done

  if [[ -n "$status_insecure" ]]; then
    echo "[FAIL] $label returned server error even with --no-check-certificate (HTTP $status_insecure): $url"
  elif [[ -n "$status" ]]; then
    echo "[FAIL] $label returned server error with TLS verification (HTTP $status): $url"
  else
    echo "[FAIL] $label unreachable from osticket container (no HTTP response): $url"
  fi
  failures=$((failures + 1))
}

echo "==> osTicket + Keycloak preflight"
check_plugin
check_url_from_osticket "$DISCOVERY_URL" "OIDC discovery"
check_url_from_osticket "$AUTH_URL" "OIDC auth endpoint"
check_url_from_osticket "$TOKEN_URL" "OIDC token endpoint"
check_url_from_osticket "$USERINFO_URL" "OIDC userinfo endpoint"

if [[ $failures -gt 0 ]]; then
  echo
  echo "Preflight completed with $failures hard failure(s)."
  exit 1
fi

echo
echo "Preflight successful."

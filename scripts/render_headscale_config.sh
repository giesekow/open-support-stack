#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${1:-.env}"
TPL="config/headscale/config.template.yaml"
OUT="config/headscale/config.yaml"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[FAIL] Missing env file: $ENV_FILE"
  exit 1
fi
if [[ ! -f "$TPL" ]]; then
  echo "[FAIL] Missing template: $TPL"
  exit 1
fi

if ! command -v sed >/dev/null 2>&1; then
  echo "[FAIL] sed is required but not installed"
  exit 1
fi

env_get() {
  local key="$1"
  local def="$2"
  local val
  val="$(
    awk -F= -v k="$key" '$1==k {sub(/^[^=]*=/, "", $0); print; exit}' "$ENV_FILE" \
      | tr -d '\r'
  )"
  if [[ -z "${val}" ]]; then
    printf '%s' "$def"
  else
    printf '%s' "$val"
  fi
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

HS_SERVER_URL="$(env_get HEADSCALE_SERVER_URL "https://mesh.example.com")"
HS_METRICS_PORT="$(env_get HEADSCALE_METRICS_PORT "9090")"
HS_V4="$(env_get HEADSCALE_IP_PREFIXES_V4 "100.64.0.0/10")"
HS_V6="$(env_get HEADSCALE_IP_PREFIXES_V6 "fd7a:115c:a1e0::/48")"
HS_DNS_BASE="$(env_get HEADSCALE_DNS_BASE_DOMAIN "support.mesh.internal")"

HS_SERVER_URL_ESCAPED="$(escape_sed_replacement "$HS_SERVER_URL")"
HS_METRICS_PORT_ESCAPED="$(escape_sed_replacement "$HS_METRICS_PORT")"
HS_V4_ESCAPED="$(escape_sed_replacement "$HS_V4")"
HS_V6_ESCAPED="$(escape_sed_replacement "$HS_V6")"
HS_DNS_BASE_ESCAPED="$(escape_sed_replacement "$HS_DNS_BASE")"

TMP_OUT="$(mktemp)"
trap 'rm -f "$TMP_OUT"' EXIT

sed \
  -e "s|__HEADSCALE_SERVER_URL__|${HS_SERVER_URL_ESCAPED}|g" \
  -e "s|__HEADSCALE_METRICS_PORT__|${HS_METRICS_PORT_ESCAPED}|g" \
  -e "s|__HEADSCALE_IP_PREFIXES_V4__|${HS_V4_ESCAPED}|g" \
  -e "s|__HEADSCALE_IP_PREFIXES_V6__|${HS_V6_ESCAPED}|g" \
  -e "s|__HEADSCALE_DNS_BASE_DOMAIN__|${HS_DNS_BASE_ESCAPED}|g" \
  "$TPL" > "$TMP_OUT"

if grep -q '__[A-Z0-9_]\+__' "$TMP_OUT"; then
  echo "[FAIL] Unresolved template placeholder(s) remain in $OUT"
  grep -o '__[A-Z0-9_]\+__' "$TMP_OUT" | sort -u
  exit 1
fi

mv "$TMP_OUT" "$OUT"

echo "[OK] Rendered $OUT from $TPL using $ENV_FILE"

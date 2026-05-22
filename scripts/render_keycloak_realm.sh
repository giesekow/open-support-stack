#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${1:-.env}"
TPL="config/keycloak/realm-support.template.json"
OUT="config/keycloak/realm-support.json"

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

BASE_DOMAIN="$(env_get BASE_DOMAIN "example.com")"
KEYCLOAK_REALM="$(env_get KEYCLOAK_REALM "support")"
SUPPORT_HOST="$(env_get SUPPORT_HOST "support.${BASE_DOMAIN}")"
SSO_HOST="$(env_get SSO_HOST "sso.${BASE_DOMAIN}")"
VAULT_HOST="$(env_get VAULT_HOST "vault.${BASE_DOMAIN}")"
DOCS_HOST="$(env_get DOCS_HOST "docs.${BASE_DOMAIN}")"
REMOTE_HOST="$(env_get REMOTE_HOST "remote.${BASE_DOMAIN}")"
MESH_WEB_HOST="$(env_get MESH_WEB_HOST "mesh-web.${BASE_DOMAIN}")"
TICKETS_HOST="$(env_get TICKETS_HOST "tickets.${BASE_DOMAIN}")"
CRM_HOST="$(env_get CRM_HOST "crm.${BASE_DOMAIN}")"
FILES_HOST="$(env_get FILES_HOST "files.${BASE_DOMAIN}")"

KEYCLOAK_REALM_ESCAPED="$(escape_sed_replacement "$KEYCLOAK_REALM")"
SUPPORT_HOST_ESCAPED="$(escape_sed_replacement "$SUPPORT_HOST")"
SSO_HOST_ESCAPED="$(escape_sed_replacement "$SSO_HOST")"
VAULT_HOST_ESCAPED="$(escape_sed_replacement "$VAULT_HOST")"
DOCS_HOST_ESCAPED="$(escape_sed_replacement "$DOCS_HOST")"
REMOTE_HOST_ESCAPED="$(escape_sed_replacement "$REMOTE_HOST")"
MESH_WEB_HOST_ESCAPED="$(escape_sed_replacement "$MESH_WEB_HOST")"
TICKETS_HOST_ESCAPED="$(escape_sed_replacement "$TICKETS_HOST")"
CRM_HOST_ESCAPED="$(escape_sed_replacement "$CRM_HOST")"
FILES_HOST_ESCAPED="$(escape_sed_replacement "$FILES_HOST")"

TMP_OUT="$(mktemp)"
trap 'rm -f "$TMP_OUT"' EXIT

sed \
  -e "s|__KEYCLOAK_REALM__|${KEYCLOAK_REALM_ESCAPED}|g" \
  -e "s|__SUPPORT_HOST__|${SUPPORT_HOST_ESCAPED}|g" \
  -e "s|__SSO_HOST__|${SSO_HOST_ESCAPED}|g" \
  -e "s|__VAULT_HOST__|${VAULT_HOST_ESCAPED}|g" \
  -e "s|__DOCS_HOST__|${DOCS_HOST_ESCAPED}|g" \
  -e "s|__REMOTE_HOST__|${REMOTE_HOST_ESCAPED}|g" \
  -e "s|__MESH_WEB_HOST__|${MESH_WEB_HOST_ESCAPED}|g" \
  -e "s|__TICKETS_HOST__|${TICKETS_HOST_ESCAPED}|g" \
  -e "s|__CRM_HOST__|${CRM_HOST_ESCAPED}|g" \
  -e "s|__FILES_HOST__|${FILES_HOST_ESCAPED}|g" \
  "$TPL" > "$TMP_OUT"

if grep -q '__[A-Z0-9_]\+__' "$TMP_OUT"; then
  echo "[FAIL] Unresolved template placeholder(s) remain in $OUT"
  grep -o '__[A-Z0-9_]\+__' "$TMP_OUT" | sort -u
  exit 1
fi

mv "$TMP_OUT" "$OUT"

echo "[OK] Rendered $OUT from $TPL using $ENV_FILE"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${1:-.env}"
TPL="nginx/html/index.template.html"
OUT="nginx/html/index.html"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[FAIL] Missing env file: $ENV_FILE"
  exit 1
fi
if [[ ! -f "$TPL" ]]; then
  echo "[FAIL] Missing template: $TPL"
  exit 1
fi

env_get() {
  local key="$1"
  local def="$2"
  local val
  val="$(awk -F= -v k="$key" '$1==k {sub(/^[^=]*=/, "", $0); print; exit}' "$ENV_FILE" | tr -d '\r')"
  if [[ -z "$val" ]]; then
    printf '%s' "$def"
  else
    printf '%s' "$val"
  fi
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

BASE_DOMAIN="$(env_get BASE_DOMAIN 'example.com')"
SUPPORT_HOST="$(env_get SUPPORT_HOST "$BASE_DOMAIN")"
SSO_HOST="$(env_get SSO_HOST "sso.${BASE_DOMAIN}")"
VAULT_HOST="$(env_get VAULT_HOST "vault.${BASE_DOMAIN}")"
DOCS_HOST="$(env_get DOCS_HOST "docs.${BASE_DOMAIN}")"
REMOTE_HOST="$(env_get REMOTE_HOST "remote.${BASE_DOMAIN}")"
MESH_HOST="$(env_get MESH_HOST "mesh.${BASE_DOMAIN}")"
MESH_WEB_HOST="$(env_get MESH_WEB_HOST "mesh-web.${BASE_DOMAIN}")"
TICKETS_HOST="$(env_get TICKETS_HOST "tickets.${BASE_DOMAIN}")"
CRM_HOST="$(env_get CRM_HOST "crm.${BASE_DOMAIN}")"
STATUS_HOST="$(env_get STATUS_HOST "status.${BASE_DOMAIN}")"
KEYCLOAK_REALM="$(env_get KEYCLOAK_REALM "support")"
PORTAL_OIDC_CLIENT_ID="$(env_get SUPPORT_PORTAL_OIDC_CLIENT_ID "$(env_get MESHWEB_OIDC_CLIENT_ID "mesh-web-ui")")"

TMP_OUT="$(mktemp)"
trap 'rm -f "$TMP_OUT"' EXIT

sed \
  -e "s|__SUPPORT_HOST__|$(escape_sed_replacement "$SUPPORT_HOST")|g" \
  -e "s|__SSO_HOST__|$(escape_sed_replacement "$SSO_HOST")|g" \
  -e "s|__VAULT_HOST__|$(escape_sed_replacement "$VAULT_HOST")|g" \
  -e "s|__DOCS_HOST__|$(escape_sed_replacement "$DOCS_HOST")|g" \
  -e "s|__REMOTE_HOST__|$(escape_sed_replacement "$REMOTE_HOST")|g" \
  -e "s|__MESH_HOST__|$(escape_sed_replacement "$MESH_HOST")|g" \
  -e "s|__MESH_WEB_HOST__|$(escape_sed_replacement "$MESH_WEB_HOST")|g" \
  -e "s|__TICKETS_HOST__|$(escape_sed_replacement "$TICKETS_HOST")|g" \
  -e "s|__CRM_HOST__|$(escape_sed_replacement "$CRM_HOST")|g" \
  -e "s|__STATUS_HOST__|$(escape_sed_replacement "$STATUS_HOST")|g" \
  -e "s|__KEYCLOAK_REALM__|$(escape_sed_replacement "$KEYCLOAK_REALM")|g" \
  -e "s|__PORTAL_OIDC_CLIENT_ID__|$(escape_sed_replacement "$PORTAL_OIDC_CLIENT_ID")|g" \
  "$TPL" > "$TMP_OUT"

if grep -q '__[A-Z0-9_]\+__' "$TMP_OUT"; then
  echo "[FAIL] Unresolved template placeholders in $OUT"
  grep -o '__[A-Z0-9_]\+__' "$TMP_OUT" | sort -u
  exit 1
fi

mv "$TMP_OUT" "$OUT"
chmod 644 "$OUT"
echo "[OK] Rendered $OUT from $TPL using $ENV_FILE"

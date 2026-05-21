#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${1:-.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file ($ENV_FILE) in $ROOT_DIR"
  exit 1
fi

env_get() {
  local key="$1"
  local def="$2"
  local val
  val="$(grep -E "^${key}=" "$ENV_FILE" | head -n1 | cut -d= -f2- || true)"
  if [[ -z "$val" ]]; then
    printf '%s' "$def"
  else
    printf '%s' "$val"
  fi
}

BASE_DOMAIN="$(env_get BASE_DOMAIN "example.com")"
SUPPORT_HOST="$(env_get SUPPORT_HOST "support.${BASE_DOMAIN}")"
MESH_WEB_HOST="$(env_get MESH_WEB_HOST "mesh-web.${BASE_DOMAIN}")"
REALM="$(env_get KEYCLOAK_REALM "support")"
CLIENT_ID="$(env_get MESHWEB_OIDC_CLIENT_ID "mesh-web-ui")"
KEYCLOAK_ADMIN_USER="$(env_get KEYCLOAK_ADMIN_USER "")"
KEYCLOAK_ADMIN_PASSWORD="$(env_get KEYCLOAK_ADMIN_PASSWORD "")"

if [[ -z "$KEYCLOAK_ADMIN_USER" || -z "$KEYCLOAK_ADMIN_PASSWORD" ]]; then
  echo "Missing KEYCLOAK_ADMIN_USER/KEYCLOAK_ADMIN_PASSWORD in $ENV_FILE"
  exit 1
fi

echo "==> Login to Keycloak admin API"
docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user "$KEYCLOAK_ADMIN_USER" \
  --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null

CLIENT_UUID="$(
  docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$CLIENT_ID" --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"

if [[ -z "$CLIENT_UUID" || "$CLIENT_UUID" == "id" ]]; then
  echo "Client '$CLIENT_ID' not found in realm '$REALM'"
  exit 1
fi

echo "==> Updating redirect URIs/web origins for client '$CLIENT_ID'"
docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$CLIENT_UUID" -r "$REALM" \
  -s "redirectUris=[\"https://${MESH_WEB_HOST}/oauth2/callback\",\"https://${SUPPORT_HOST}/oauth2/callback\"]" \
  -s "webOrigins=[\"https://${MESH_WEB_HOST}\",\"https://${SUPPORT_HOST}\"]" \
  >/dev/null

echo "Done. Client '$CLIENT_ID' now allows:"
echo "  - https://${MESH_WEB_HOST}/oauth2/callback"
echo "  - https://${SUPPORT_HOST}/oauth2/callback"

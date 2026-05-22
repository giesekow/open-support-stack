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
DOCS_HOST="$(env_get DOCS_HOST "docs.${BASE_DOMAIN}")"
REMOTE_HOST="$(env_get REMOTE_HOST "remote.${BASE_DOMAIN}")"
TICKETS_HOST="$(env_get TICKETS_HOST "tickets.${BASE_DOMAIN}")"
CRM_HOST="$(env_get CRM_HOST "crm.${BASE_DOMAIN}")"
FILES_HOST="$(env_get FILES_HOST "files.${BASE_DOMAIN}")"
PENPOT_HOST="$(env_get PENPOT_HOST "penpot.${BASE_DOMAIN}")"
REALM="$(env_get KEYCLOAK_REALM "support")"
MESHWEB_CLIENT_ID="$(env_get MESHWEB_OIDC_CLIENT_ID "mesh-web-ui")"
PORTAL_CLIENT_ID="$(env_get SUPPORT_PORTAL_OIDC_CLIENT_ID "support-portal")"
GUAC_CLIENT_ID="$(env_get GUACAMOLE_OPENID_CLIENT_ID "guacamole")"
BOOKSTACK_CLIENT_ID="$(env_get BOOKSTACK_OIDC_CLIENT_ID "bookstack")"
OSTICKET_CLIENT_ID="$(env_get OSTICKET_OIDC_CLIENT_ID "osticket")"
ESPOCRM_CLIENT_ID="$(env_get ESPOCRM_OIDC_CLIENT_ID "espocrm")"
SEAFILE_CLIENT_ID="$(env_get SEAFILE_OIDC_CLIENT_ID "seafile")"
PENPOT_CLIENT_ID="$(env_get PENPOT_OIDC_CLIENT_ID "penpot")"
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

MESHWEB_CLIENT_UUID="$(
  docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$MESHWEB_CLIENT_ID" --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"

if [[ -z "$MESHWEB_CLIENT_UUID" || "$MESHWEB_CLIENT_UUID" == "id" ]]; then
  echo "Client '$MESHWEB_CLIENT_ID' not found in realm '$REALM'"
  exit 1
fi

echo "==> Updating redirect URIs/web origins for client '$MESHWEB_CLIENT_ID'"
docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$MESHWEB_CLIENT_UUID" -r "$REALM" \
  -s "redirectUris=[\"https://${MESH_WEB_HOST}/oauth2/callback\"]" \
  -s "webOrigins=[\"https://${MESH_WEB_HOST}\"]" \
  >/dev/null

PORTAL_CLIENT_UUID="$(
  docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$PORTAL_CLIENT_ID" --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"

if [[ -z "$PORTAL_CLIENT_UUID" || "$PORTAL_CLIENT_UUID" == "id" ]]; then
  echo "Client '$PORTAL_CLIENT_ID' not found in realm '$REALM'"
  exit 1
fi

echo "==> Updating redirect URIs/web origins for client '$PORTAL_CLIENT_ID'"
docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$PORTAL_CLIENT_UUID" -r "$REALM" \
  -s "redirectUris=[\"https://${SUPPORT_HOST}/oauth2/callback\"]" \
  -s "webOrigins=[\"https://${SUPPORT_HOST}\"]" \
  >/dev/null

GUAC_CLIENT_UUID="$(
  docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$GUAC_CLIENT_ID" --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"

if [[ -z "$GUAC_CLIENT_UUID" || "$GUAC_CLIENT_UUID" == "id" ]]; then
  echo "Client '$GUAC_CLIENT_ID' not found in realm '$REALM'"
  exit 1
fi

echo "==> Updating redirect URIs/web origins for client '$GUAC_CLIENT_ID'"
docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$GUAC_CLIENT_UUID" -r "$REALM" \
  -s "redirectUris=[\"https://${REMOTE_HOST}/guacamole/*\",\"https://${REMOTE_HOST}/guacamole/\"]" \
  -s "webOrigins=[\"https://${REMOTE_HOST}\"]" \
  >/dev/null

BOOKSTACK_CLIENT_UUID="$(
  docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$BOOKSTACK_CLIENT_ID" --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"

if [[ -z "$BOOKSTACK_CLIENT_UUID" || "$BOOKSTACK_CLIENT_UUID" == "id" ]]; then
  echo "Client '$BOOKSTACK_CLIENT_ID' not found in realm '$REALM'"
  exit 1
fi

echo "==> Updating redirect URIs/web origins for client '$BOOKSTACK_CLIENT_ID'"
docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$BOOKSTACK_CLIENT_UUID" -r "$REALM" \
  -s "redirectUris=[\"https://${DOCS_HOST}/oidc/callback\",\"https://${DOCS_HOST}/*\"]" \
  -s "webOrigins=[\"https://${DOCS_HOST}\"]" \
  >/dev/null

OSTICKET_CLIENT_UUID="$(
  docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$OSTICKET_CLIENT_ID" --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"

if [[ -z "$OSTICKET_CLIENT_UUID" || "$OSTICKET_CLIENT_UUID" == "id" ]]; then
  echo "Client '$OSTICKET_CLIENT_ID' not found in realm '$REALM'"
  exit 1
fi

echo "==> Updating redirect URIs/web origins for client '$OSTICKET_CLIENT_ID'"
docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$OSTICKET_CLIENT_UUID" -r "$REALM" \
  -s "redirectUris=[\"https://${TICKETS_HOST}/auth/oauth2\",\"https://${TICKETS_HOST}/*\"]" \
  -s "webOrigins=[\"https://${TICKETS_HOST}\"]" \
  >/dev/null

ESPOCRM_CLIENT_UUID="$(
  docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$ESPOCRM_CLIENT_ID" --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"

if [[ -z "$ESPOCRM_CLIENT_UUID" || "$ESPOCRM_CLIENT_UUID" == "id" ]]; then
  echo "Client '$ESPOCRM_CLIENT_ID' not found in realm '$REALM'"
  exit 1
fi

echo "==> Updating redirect URIs/web origins for client '$ESPOCRM_CLIENT_ID'"
docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$ESPOCRM_CLIENT_UUID" -r "$REALM" \
  -s "redirectUris=[\"https://${CRM_HOST}/oauth-callback.php\",\"https://${CRM_HOST}/*\"]" \
  -s "webOrigins=[\"https://${CRM_HOST}\"]" \
  >/dev/null

SEAFILE_CLIENT_UUID="$(
  docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$SEAFILE_CLIENT_ID" --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"

if [[ -z "$SEAFILE_CLIENT_UUID" || "$SEAFILE_CLIENT_UUID" == "id" ]]; then
  echo "Client '$SEAFILE_CLIENT_ID' not found in realm '$REALM'"
  exit 1
fi

echo "==> Updating redirect URIs/web origins for client '$SEAFILE_CLIENT_ID'"
docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$SEAFILE_CLIENT_UUID" -r "$REALM" \
  -s "redirectUris=[\"https://${FILES_HOST}/*\"]" \
  -s "webOrigins=[\"https://${FILES_HOST}\"]" \
  >/dev/null

PENPOT_CLIENT_UUID="$(
  docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh get clients -r "$REALM" -q clientId="$PENPOT_CLIENT_ID" --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"

if [[ -z "$PENPOT_CLIENT_UUID" || "$PENPOT_CLIENT_UUID" == "id" ]]; then
  echo "Client '$PENPOT_CLIENT_ID' not found in realm '$REALM'"
  exit 1
fi

echo "==> Updating redirect URIs/web origins for client '$PENPOT_CLIENT_ID'"
docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh update "clients/$PENPOT_CLIENT_UUID" -r "$REALM" \
  -s "redirectUris=[\"https://${PENPOT_HOST}/api/auth/oidc/callback\",\"https://${PENPOT_HOST}/*\"]" \
  -s "webOrigins=[\"https://${PENPOT_HOST}\"]" \
  >/dev/null

echo "Done. Client '$MESHWEB_CLIENT_ID' now allows:"
echo "  - https://${MESH_WEB_HOST}/oauth2/callback"
echo "Done. Client '$PORTAL_CLIENT_ID' now allows:"
echo "  - https://${SUPPORT_HOST}/oauth2/callback"
echo "Done. Client '$GUAC_CLIENT_ID' now allows:"
echo "  - https://${REMOTE_HOST}/guacamole/*"
echo "Done. Client '$BOOKSTACK_CLIENT_ID' now allows:"
echo "  - https://${DOCS_HOST}/oidc/callback"
echo "Done. Client '$OSTICKET_CLIENT_ID' now allows:"
echo "  - https://${TICKETS_HOST}/auth/oauth2"
echo "Done. Client '$ESPOCRM_CLIENT_ID' now allows:"
echo "  - https://${CRM_HOST}/oauth-callback.php"
echo "Done. Client '$SEAFILE_CLIENT_ID' now allows:"
echo "  - https://${FILES_HOST}/*"
echo "Done. Client '$PENPOT_CLIENT_ID' now allows:"
echo "  - https://${PENPOT_HOST}/api/auth/oidc/callback"

#!/usr/bin/env bash
set -euo pipefail

# Seeds one admin identity across the stack:
# 1) Keycloak user
# 2) BookStack admin user linked to Keycloak external auth ID
# 3) Guacamole admin user
# 4) Vaultwarden note/config alignment (no global per-user admin exists)
#
# Usage:
#   scripts/seed_admin_accounts.sh \
#     --email admin@example.com \
#     --name "Support Admin" \
#     --password "ChangeMeNow123!"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f .env ]]; then
  echo "Missing .env in $ROOT_DIR"
  exit 1
fi

EMAIL=""
NAME=""
PASSWORD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --email) EMAIL="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
    --password) PASSWORD="${2:-}"; shift 2 ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$EMAIL" || -z "$NAME" || -z "$PASSWORD" ]]; then
  echo "Usage: $0 --email <email> --name <display name> --password <password>"
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

if [[ -z "${KEYCLOAK_ADMIN_USER:-}" || -z "${KEYCLOAK_ADMIN_PASSWORD:-}" ]]; then
  echo "Missing KEYCLOAK_ADMIN_USER/KEYCLOAK_ADMIN_PASSWORD in .env"
  exit 1
fi

if [[ -z "${BOOKSTACK_DB_USER:-}" || -z "${BOOKSTACK_DB_PASSWORD:-}" || -z "${BOOKSTACK_DB_DATABASE:-}" ]]; then
  echo "Missing BookStack DB credentials in .env"
  exit 1
fi

if [[ -z "${GUACAMOLE_DB_USER:-}" || -z "${GUACAMOLE_DB_PASSWORD:-}" || -z "${GUACAMOLE_DB_NAME:-}" ]]; then
  echo "Missing Guacamole DB credentials in .env"
  exit 1
fi

echo "==> [1/4] Keycloak: create/update user $EMAIL"
docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user "$KEYCLOAK_ADMIN_USER" \
  --password "$KEYCLOAK_ADMIN_PASSWORD" >/dev/null

KEYCLOAK_USER_ID="$(
  docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh get users -r support -q email="$EMAIL" --fields id --format csv --noquotes \
    | tr -d '\r' | tail -n 1
)"

if [[ -z "$KEYCLOAK_USER_ID" || "$KEYCLOAK_USER_ID" == "id" ]]; then
  docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh create users -r support \
    -s "username=$EMAIL" \
    -s enabled=true \
    -s "email=$EMAIL" \
    -s emailVerified=true \
    -s "firstName=$NAME" \
    -s "lastName=Admin" >/dev/null

  KEYCLOAK_USER_ID="$(
    docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh get users -r support -q email="$EMAIL" --fields id --format csv --noquotes \
      | tr -d '\r' | tail -n 1
  )"
else
  docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh update "users/$KEYCLOAK_USER_ID" -r support \
    -s enabled=true \
    -s "email=$EMAIL" \
    -s emailVerified=true \
    -s "firstName=$NAME" >/dev/null
fi

docker compose exec -T keycloak /opt/keycloak/bin/kcadm.sh set-password -r support \
  --userid "$KEYCLOAK_USER_ID" \
  --new-password "$PASSWORD" >/dev/null

echo "    Keycloak user id: $KEYCLOAK_USER_ID"

echo "==> [2/4] BookStack: create/link admin user"
# Ensure user exists as admin (no-op if already exists).
docker compose exec -T bookstack sh -lc \
  "php /app/www/artisan bookstack:create-admin --email='$EMAIL' --name='$NAME' --password='$PASSWORD' --external-auth-id='$KEYCLOAK_USER_ID' --no-interaction" \
  >/dev/null 2>&1 || true

# Force-link existing account to Keycloak and ensure admin role assignment.
docker compose exec -T bookstack-db mariadb \
  -u"$BOOKSTACK_DB_USER" \
  -p"$BOOKSTACK_DB_PASSWORD" \
  -D "$BOOKSTACK_DB_DATABASE" \
  -e "
UPDATE users SET external_auth_id='${KEYCLOAK_USER_ID}' WHERE email='${EMAIL}';
INSERT IGNORE INTO role_user (user_id, role_id)
SELECT u.id, r.id
FROM users u
JOIN roles r ON r.system_name='admin'
WHERE u.email='${EMAIL}';
" >/dev/null

echo "    BookStack user linked and admin role ensured."

echo "==> [3/4] Guacamole: create/update admin user"
GUAC_HEX_HASH="$(printf '%s' "$PASSWORD" | sha256sum | awk '{print toupper($1)}')"

docker compose exec -T guacamole-db psql \
  -U "$GUACAMOLE_DB_USER" \
  -d "$GUACAMOLE_DB_NAME" \
  -v ON_ERROR_STOP=1 \
  -c "
INSERT INTO guacamole_entity (name, type)
VALUES ('${EMAIL}', 'USER')
ON CONFLICT (type, name) DO NOTHING;

INSERT INTO guacamole_user (entity_id, password_hash, password_salt, password_date, full_name, email_address, disabled, expired)
SELECT e.entity_id, decode('${GUAC_HEX_HASH}','hex'), NULL, NOW(), '${NAME}', '${EMAIL}', FALSE, FALSE
FROM guacamole_entity e
WHERE e.type='USER' AND e.name='${EMAIL}'
  AND NOT EXISTS (
    SELECT 1 FROM guacamole_user u WHERE u.entity_id=e.entity_id
  );

UPDATE guacamole_user u
SET password_hash=decode('${GUAC_HEX_HASH}','hex'),
    password_salt=NULL,
    password_date=NOW(),
    full_name='${NAME}',
    email_address='${EMAIL}',
    disabled=FALSE,
    expired=FALSE
FROM guacamole_entity e
WHERE e.entity_id=u.entity_id AND e.type='USER' AND e.name='${EMAIL}';

INSERT INTO guacamole_system_permission (entity_id, permission)
SELECT e.entity_id, p.permission::guacamole_system_permission_type
FROM guacamole_entity e
CROSS JOIN (
  VALUES
    ('CREATE_CONNECTION'),
    ('CREATE_CONNECTION_GROUP'),
    ('CREATE_SHARING_PROFILE'),
    ('CREATE_USER'),
    ('CREATE_USER_GROUP'),
    ('ADMINISTER')
) AS p(permission)
WHERE e.type='USER' AND e.name='${EMAIL}'
ON CONFLICT DO NOTHING;

INSERT INTO guacamole_user_permission (entity_id, affected_user_id, permission)
SELECT e.entity_id, u.user_id, p.permission::guacamole_object_permission_type
FROM guacamole_entity e
JOIN guacamole_user u ON u.entity_id=e.entity_id
CROSS JOIN (
  VALUES ('READ'), ('UPDATE'), ('ADMINISTER')
) AS p(permission)
WHERE e.type='USER' AND e.name='${EMAIL}'
ON CONFLICT DO NOTHING;
" >/dev/null

echo "    Guacamole user seeded with system admin permissions."

echo "==> [4/4] Vaultwarden note"
echo "    Vaultwarden has no per-user 'global admin' role like Keycloak/BookStack/Guacamole."
echo "    Global admin access is controlled by ADMIN_TOKEN (/admin)."
echo "    User '$EMAIL' can be created by signing up at: ${VAULTWARDEN_DOMAIN:-https://vault.example.com}"
echo "    Current SIGNUPS_ALLOWED=${VAULTWARDEN_SIGNUPS_ALLOWED:-unknown}"
echo
echo "Done."

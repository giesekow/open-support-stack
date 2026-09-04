#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE=".env"
OIDC_USERNAME=""

usage() {
  echo "Usage: $0 [--env-file <path>] --username <Keycloak preferred_username>"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="${2:-}"
      shift 2
      ;;
    --username)
      OIDC_USERNAME="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$OIDC_USERNAME" ]]; then
  echo "Missing --username. Use the exact Keycloak preferred_username value." >&2
  usage >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Environment file not found: $ENV_FILE" >&2
  exit 1
fi

env_get() {
  local key="$1"
  local value

  value="$(sed -n "s/^${key}=//p" "$ENV_FILE" | tail -n 1 | tr -d '\r')"
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value="${value:1:${#value}-2}"
  fi

  printf '%s' "$value"
}

GUACAMOLE_DB_USER="$(env_get GUACAMOLE_DB_USER)"
GUACAMOLE_DB_NAME="$(env_get GUACAMOLE_DB_NAME)"

if [[ -z "${GUACAMOLE_DB_USER:-}" || -z "${GUACAMOLE_DB_NAME:-}" ]]; then
  echo "Missing GUACAMOLE_DB_USER or GUACAMOLE_DB_NAME in $ENV_FILE" >&2
  exit 1
fi

echo "Granting Guacamole administrator permissions to OIDC user: $OIDC_USERNAME"

docker compose --env-file "$ENV_FILE" exec -T guacamole-db psql \
  -U "$GUACAMOLE_DB_USER" \
  -d "$GUACAMOLE_DB_NAME" \
  -v ON_ERROR_STOP=1 \
  -v oidc_username="$OIDC_USERNAME" <<'SQL'
BEGIN;

INSERT INTO guacamole_entity (name, type)
VALUES (:'oidc_username', 'USER')
ON CONFLICT (type, name) DO NOTHING;

-- PostgreSQL requires a user row for permissions. The random hash does not
-- expose or alter the user's Keycloak credentials; OIDC remains the login path.
INSERT INTO guacamole_user (
  entity_id,
  password_hash,
  password_salt,
  password_date,
  full_name,
  disabled,
  expired
)
SELECT
  e.entity_id,
  decode(md5(random()::text) || md5(clock_timestamp()::text), 'hex'),
  NULL,
  NOW(),
  :'oidc_username',
  FALSE,
  FALSE
FROM guacamole_entity e
WHERE e.type = 'USER'
  AND e.name = :'oidc_username'
ON CONFLICT (entity_id) DO UPDATE
SET disabled = FALSE,
    expired = FALSE;

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
WHERE e.type = 'USER'
  AND e.name = :'oidc_username'
ON CONFLICT DO NOTHING;

INSERT INTO guacamole_user_permission (entity_id, affected_user_id, permission)
SELECT e.entity_id, u.user_id, p.permission::guacamole_object_permission_type
FROM guacamole_entity e
JOIN guacamole_user u ON u.entity_id = e.entity_id
CROSS JOIN (VALUES ('READ'), ('UPDATE'), ('ADMINISTER')) AS p(permission)
WHERE e.type = 'USER'
  AND e.name = :'oidc_username'
ON CONFLICT DO NOTHING;

COMMIT;

SELECT e.name AS username, sp.permission
FROM guacamole_entity e
JOIN guacamole_system_permission sp ON sp.entity_id = e.entity_id
WHERE e.type = 'USER'
  AND e.name = :'oidc_username'
ORDER BY sp.permission;
SQL

echo
echo "Guacamole administrator permissions granted. Log out of Guacamole and sign in again through Keycloak."

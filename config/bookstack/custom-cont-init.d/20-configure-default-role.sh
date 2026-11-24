#!/usr/bin/with-contenv bash
set -euo pipefail

role_name="${BOOKSTACK_DEFAULT_REGISTRATION_ROLE:-Viewer}"
role_name_pattern='^[A-Za-z0-9][A-Za-z0-9 _-]{0,190}$'

if [[ ! "$role_name" =~ $role_name_pattern ]]; then
  echo "Invalid BOOKSTACK_DEFAULT_REGISTRATION_ROLE" >&2
  exit 1
fi

role_id="$({
  mariadb --batch --skip-column-names \
    --host="$DB_HOST" --port="${DB_PORT:-3306}" \
    --user="$DB_USERNAME" --password="$DB_PASSWORD" "$DB_DATABASE" \
    --execute="SELECT id FROM roles WHERE display_name='${role_name}' AND system_name='' ORDER BY id;"
} 2>/dev/null)"

if [[ ! "$role_id" =~ ^[0-9]+$ ]]; then
  echo "BookStack default role '$role_name' was not found or was ambiguous" >&2
  exit 1
fi

mariadb \
  --host="$DB_HOST" --port="${DB_PORT:-3306}" \
  --user="$DB_USERNAME" --password="$DB_PASSWORD" "$DB_DATABASE" \
  --execute="
    INSERT INTO settings(setting_key, value, created_at, updated_at, type)
    VALUES ('registration-role', '${role_id}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'string')
    ON DUPLICATE KEY UPDATE value=VALUES(value), updated_at=CURRENT_TIMESTAMP, type='string';
  "

echo "Configured BookStack default registration role: $role_name (id $role_id)"

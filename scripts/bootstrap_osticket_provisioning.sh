#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${1:-.env}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "[ERROR] Environment file not found: $ENV_FILE" >&2
  exit 1
fi

env_value() {
  local name="$1" default="$2" value
  value="$(sed -n "s/^${name}=//p" "$ENV_FILE" | tail -n 1)"
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  printf '%s' "${value:-$default}"
}

department="$(env_value PROVISIONING_OSTICKET_DEPARTMENT_NAME Support)"
role="$(env_value PROVISIONING_OSTICKET_ROLE_NAME 'Support Agent')"
signature="$(env_value PROVISIONING_OSTICKET_SCHEMA_SIGNATURE 83a22ba22b1a6a624fcb1da03882ac1b)"

for value in "$department" "$role" "$signature"; do
  if [[ ! "$value" =~ ^[A-Za-z0-9._[:space:]-]+$ ]]; then
    echo "[ERROR] Unsafe osTicket provisioning value: $value" >&2
    exit 1
  fi
done

compose=(docker compose --env-file "$ENV_FILE")
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="backups/osticket"
backup_file="$backup_dir/pre-provisioning-$timestamp.sql.gz"
mkdir -p "$backup_dir"

echo "[INFO] Creating osTicket database backup: $backup_file"
"${compose[@]}" exec -T osticket-db sh -lc \
  'mariadb-dump --single-transaction -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"' \
  | gzip -9 >"$backup_file"
test -s "$backup_file"

sql=$(cat <<SQL
SET @actual_signature = (
  SELECT value FROM ost_config
  WHERE namespace='core' AND \`key\`='schema_signature'
);
SELECT IF(@actual_signature='$signature', 'schema-ok', CONCAT('schema-mismatch:', COALESCE(@actual_signature, 'missing'))) AS schema_check;
INSERT INTO ost_role (flags,name,permissions,notes,created,updated)
SELECT 1,'$role','{"ticket.reply":1}','Managed least-privilege role for Keycloak employee provisioning',UTC_TIMESTAMP(),UTC_TIMESTAMP()
WHERE @actual_signature='$signature'
  AND NOT EXISTS (SELECT 1 FROM ost_role WHERE name='$role');
SELECT d.id AS department_id,d.name AS department_name,r.id AS role_id,r.name AS role_name,r.permissions
FROM ost_department d JOIN ost_role r
WHERE d.name='$department' AND r.name='$role';
SQL
)

output=$(printf '%s\n' "$sql" | "${compose[@]}" exec -T osticket-db sh -lc \
  'mariadb --batch --raw -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE"')
printf '%s\n' "$output"

if ! grep -q $'^schema-ok\t\|^schema-ok$' <<<"$output"; then
  echo "[ERROR] osTicket schema is not the approved baseline; role bootstrap stopped" >&2
  exit 1
fi
if ! grep -Fq "$role"$'\t''{"ticket.reply":1}' <<<"$output"; then
  echo "[ERROR] osTicket least-privilege role verification failed" >&2
  exit 1
fi

echo "[OK] osTicket provisioning placement is ready; keep the target disabled/dry-run until review"

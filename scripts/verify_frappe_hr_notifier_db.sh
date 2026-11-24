#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${1:-.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  if [[ -f "$ROOT_DIR/$ENV_FILE" ]]; then
    ENV_FILE="$ROOT_DIR/$ENV_FILE"
  else
    echo "Environment file not found: $ENV_FILE" >&2
    exit 1
  fi
fi

docker compose --project-directory "$ROOT_DIR" --env-file "$ENV_FILE" \
  run --rm --no-deps --entrypoint python frappe-hr-leave-notifier - <<'PY'
import os

import pymysql


connection = pymysql.connect(
    host=os.environ["FRAPPE_HR_DB_HOST"],
    port=int(os.environ.get("FRAPPE_HR_DB_PORT", "3306")),
    user=os.environ["FRAPPE_HR_DB_USER"],
    password=os.environ["FRAPPE_HR_DB_PASSWORD"],
    autocommit=True,
)

with connection.cursor() as cursor:
    cursor.execute(
        """
        SELECT TABLE_SCHEMA, PRIVILEGE_TYPE
        FROM information_schema.SCHEMA_PRIVILEGES
        WHERE GRANTEE = CONCAT(
            "'", SUBSTRING_INDEX(CURRENT_USER(), '@', 1),
            "'@'", SUBSTRING_INDEX(CURRENT_USER(), '@', -1), "'"
        )
        ORDER BY TABLE_SCHEMA, PRIVILEGE_TYPE
        """
    )
    privileges = cursor.fetchall()
    if len(privileges) != 1 or privileges[0][1] != "SELECT":
        raise SystemExit(f"Unexpected schema privileges: {privileges}")
    schema = privileges[0][0]
    print(f"schema_privileges={schema}:SELECT")

    connection.select_db(schema)
    cursor.execute("SELECT COUNT(*) FROM `tabLeave Application`")
    print(f"leave_application_read_count={cursor.fetchone()[0]}")

    try:
        cursor.execute("CREATE TABLE `__notifier_write_probe` (`id` INT)")
    except pymysql.MySQLError as exc:
        if exc.args[0] not in (1044, 1142):
            raise
        print(f"write_denied=yes error_code={exc.args[0]}")
    else:
        cursor.execute("DROP TABLE `__notifier_write_probe`")
        raise SystemExit("Notifier account unexpectedly has write access")

connection.close()
PY

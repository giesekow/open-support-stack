#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${1:-.env.production}"
OUTPUT_DIR="${2:-backups/orangehrm-frappe-hr-$(date -u +%Y%m%dT%H%M%SZ)}"
[[ -f "$ENV_FILE" ]] || { echo "Missing environment file: $ENV_FILE" >&2; exit 1; }

env_get() {
  awk -F= -v key="$1" '$1 == key {sub(/^[^=]*=/, ""); gsub(/^[\047"]|[\047"]$/, ""); print; exit}' "$ENV_FILE"
}

DB_NAME="$(env_get ORANGEHRM_DB_NAME)"
ROOT_PASSWORD="$(env_get ORANGEHRM_DB_ROOT_PASSWORD)"
[[ -n "$DB_NAME" && -n "$ROOT_PASSWORD" ]] || {
  echo "ORANGEHRM_DB_NAME and ORANGEHRM_DB_ROOT_PASSWORD are required" >&2
  exit 1
}

mapfile -t VOLUMES < <(docker volume ls \
  --filter label=com.docker.compose.volume=orangehrm-db-data \
  --format '{{.Name}}')
if [[ ${#VOLUMES[@]} -ne 1 ]]; then
  echo "Expected exactly one OrangeHRM database volume, found ${#VOLUMES[@]}." >&2
  echo "Set ORANGEHRM_DB_VOLUME in $ENV_FILE when more than one stack exists." >&2
  VOLUME="$(env_get ORANGEHRM_DB_VOLUME)"
  [[ -n "$VOLUME" ]] || exit 1
else
  VOLUME="${VOLUMES[0]}"
fi

mapfile -t ACTIVE_USERS < <(docker ps --filter "volume=$VOLUME" --format '{{.Names}}')
if [[ ${#ACTIVE_USERS[@]} -gt 0 ]]; then
  echo "Refusing to mount $VOLUME while it is used by: ${ACTIVE_USERS[*]}" >&2
  echo "Complete the change freeze, stop the OrangeHRM database, and run the export again." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
chmod 700 "$OUTPUT_DIR"
CONTAINER="support-orangehrm-export-$$"
cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --name "$CONTAINER" \
  -e MYSQL_ROOT_PASSWORD="$ROOT_PASSWORD" \
  -v "$VOLUME:/var/lib/mysql" \
  mariadb:11.4 --skip-networking >/dev/null

for _ in $(seq 1 60); do
  docker exec "$CONTAINER" mariadb-admin ping -uroot -p"$ROOT_PASSWORD" --silent >/dev/null 2>&1 && break
  sleep 1
done
docker exec "$CONTAINER" mariadb-admin ping -uroot -p"$ROOT_PASSWORD" --silent >/dev/null

required=(hs_hr_employee ohrm_leave ohrm_leave_type ohrm_subunit hs_hr_emp_locations ohrm_location)
for table in "${required[@]}"; do
  found="$(docker exec "$CONTAINER" mariadb -uroot -p"$ROOT_PASSWORD" -N -e \
    "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='${DB_NAME}' AND TABLE_NAME='${table}'")"
  [[ "$found" == 1 ]] || { echo "Required table is missing: $DB_NAME.$table" >&2; exit 1; }
done

query() {
  docker exec "$CONTAINER" mariadb -uroot -p"$ROOT_PASSWORD" \
    --batch --raw "$DB_NAME" -e "$1"
}

query "SELECT e.emp_number, e.employee_id, e.emp_firstname, e.emp_middle_name,
 e.emp_lastname, e.emp_work_email, e.emp_birthday, e.emp_gender, e.joined_date,
 su.name AS subunit, GROUP_CONCAT(DISTINCT loc.name ORDER BY loc.name SEPARATOR ', ') AS locations,
 e.termination_id, e.purged_at
 FROM hs_hr_employee e
 LEFT JOIN ohrm_subunit su ON su.id=e.work_station
 LEFT JOIN hs_hr_emp_locations el ON el.emp_number=e.emp_number
 LEFT JOIN ohrm_location loc ON loc.id=el.location_id
 GROUP BY e.emp_number, e.employee_id, e.emp_firstname, e.emp_middle_name,
 e.emp_lastname, e.emp_work_email, e.emp_birthday, e.emp_gender, e.joined_date,
 su.name, e.termination_id, e.purged_at
 ORDER BY e.emp_number" >"$OUTPUT_DIR/employees.tsv"

query "SELECT l.id, l.date, l.status, l.length_days, l.start_time, l.end_time,
 e.emp_number, e.employee_id, e.emp_work_email, lt.name AS leave_type,
 su.name AS subunit, GROUP_CONCAT(DISTINCT loc.name ORDER BY loc.name SEPARATOR ', ') AS locations
 FROM ohrm_leave l
 JOIN hs_hr_employee e ON e.emp_number=l.emp_number
 JOIN ohrm_leave_type lt ON lt.id=l.leave_type_id
 LEFT JOIN ohrm_subunit su ON su.id=e.work_station
 LEFT JOIN hs_hr_emp_locations el ON el.emp_number=e.emp_number
 LEFT JOIN ohrm_location loc ON loc.id=el.location_id
 GROUP BY l.id, l.date, l.status, l.length_days, l.start_time, l.end_time,
 e.emp_number, e.employee_id, e.emp_work_email, lt.name, su.name
 ORDER BY l.date, l.id" >"$OUTPUT_DIR/leave.tsv"

cat >"$OUTPUT_DIR/README.txt" <<EOF
Created UTC: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Source volume: $VOLUME
Source database: $DB_NAME
Format: tab-separated UTF-8 with a header row
Handling: contains personal/HR data; restrict access and delete under the approved retention policy.
EOF
(cd "$OUTPUT_DIR" && sha256sum employees.tsv leave.tsv README.txt >SHA256SUMS)
chmod 600 "$OUTPUT_DIR"/*
echo "OrangeHRM export created at $OUTPUT_DIR"
echo "Review SHA256SUMS and reconcile each employee before Frappe HR onboarding."

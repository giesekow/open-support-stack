#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE=".env"
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="$2"
      shift 2
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing environment file: $ENV_FILE" >&2
  exit 1
fi

env_get() {
  local key="$1"
  awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); gsub(/^['\''\"]|['\''\"]$/, ""); print; exit}' "$ENV_FILE"
}

SITE_NAME="$(env_get ERPNEXT_SITE_NAME)"
if [[ -z "$SITE_NAME" ]]; then
  echo "ERPNEXT_SITE_NAME is missing from $ENV_FILE" >&2
  exit 1
fi

if [[ " ${ARGS[*]} " != *" --email "* ]]; then
  cat >&2 <<'EOF'
Usage: ./scripts/onboard_frappe_hr_employee.sh --env-file .env \
  --email employee@example.com --employee-number EMP-0001 \
  --gender Female --date-of-birth 1990-01-01 --date-of-joining 2026-01-01 \
  --company "Bonescreen GmbH" [--department Support] [--designation Engineer] [--branch Berlin]
EOF
  exit 2
fi

COMPOSE=(docker compose --env-file "$ENV_FILE")
"${COMPOSE[@]}" cp scripts/frappe_hr_onboard.py erpnext-backend:/tmp/frappe_hr_onboard.py >/dev/null
"${COMPOSE[@]}" exec -T erpnext-backend \
  /home/frappe/frappe-bench/env/bin/python /tmp/frappe_hr_onboard.py \
  --site "$SITE_NAME" "${ARGS[@]}"

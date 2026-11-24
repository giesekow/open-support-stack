#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${1:-.env}"
[[ -f "$ENV_FILE" ]] || { echo "Missing environment file: $ENV_FILE" >&2; exit 1; }

env_get() {
  awk -F= -v key="$1" '$1 == key {sub(/^[^=]*=/, ""); gsub(/^[\047"]|[\047"]$/, ""); print; exit}' "$ENV_FILE"
}

SITE_NAME="$(env_get ERPNEXT_SITE_NAME)"
[[ -n "$SITE_NAME" ]] || { echo "ERPNEXT_SITE_NAME is missing from $ENV_FILE" >&2; exit 1; }

COMPOSE=(docker compose --env-file "$ENV_FILE")
"${COMPOSE[@]}" cp scripts/frappe_hr_configure.py erpnext-backend:/tmp/frappe_hr_configure.py >/dev/null
"${COMPOSE[@]}" exec -T erpnext-backend \
  /home/frappe/frappe-bench/env/bin/python /tmp/frappe_hr_configure.py --site "$SITE_NAME"

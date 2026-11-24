#!/usr/bin/env bash
set -Eeuo pipefail

ENV_FILE="${1:-.env}"
COMPOSE=(docker compose --env-file "$ENV_FILE")

cleanup() {
  "${COMPOSE[@]}" exec -T support-tools-db sh -c     'dropdb -U "$POSTGRES_USER" --if-exists support_tools_reconciliation_test' >/dev/null
}
trap cleanup EXIT

"${COMPOSE[@]}" build support-tools
"${COMPOSE[@]}" up -d support-tools
"${COMPOSE[@]}" exec -T support-tools-db sh -c   'dropdb -U "$POSTGRES_USER" --if-exists support_tools_reconciliation_test &&
   createdb -U "$POSTGRES_USER" support_tools_reconciliation_test'

"${COMPOSE[@]}" exec -T support-tools sh -c '
  TEST_URL="${DATABASE_URL%/*}/support_tools_reconciliation_test"
  DATABASE_URL="$TEST_URL" alembic upgrade head
  PROVISIONING_INTEGRATION_TEST=1 DATABASE_URL="$TEST_URL" \
    python -m unittest discover -s tests -v
'

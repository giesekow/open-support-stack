#!/bin/bash
set -euo pipefail

docker compose down

if [[ -x ./scripts/render_headscale_config.sh ]]; then
  ./scripts/render_headscale_config.sh .env
fi

if [[ -x ./scripts/render_keycloak_realm.sh ]]; then
  ./scripts/render_keycloak_realm.sh .env
fi

if [[ -x ./scripts/render_portal_index.sh ]]; then
  ./scripts/render_portal_index.sh .env
fi

docker compose up -d

if [[ -x ./scripts/check_osticket_keycloak.sh ]]; then
  ./scripts/check_osticket_keycloak.sh || true
fi

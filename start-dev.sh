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

if [[ -x ./scripts/sync_keycloak_redirects.sh ]]; then
  for i in 1 2 3 4 5; do
    if ./scripts/sync_keycloak_redirects.sh .env; then
      break
    fi
    if [[ "$i" -lt 5 ]]; then
      sleep 5
    else
      echo "[WARN] Failed to sync Keycloak redirect URIs after 5 attempts."
    fi
  done
fi

if [[ -x ./scripts/check_osticket_keycloak.sh ]]; then
  ./scripts/check_osticket_keycloak.sh || true
fi

if [[ -x ./scripts/configure_seafile_csrf.sh ]]; then
  ./scripts/configure_seafile_csrf.sh .env || true
fi

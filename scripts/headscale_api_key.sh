#!/usr/bin/env bash
set -euo pipefail

# Helper for Headscale API keys.
#
# Usage:
#   scripts/headscale_api_key.sh create
#   scripts/headscale_api_key.sh list
#   scripts/headscale_api_key.sh expire --prefix <key-prefix>
#
# Notes:
# - `create` prints the full token once.
# - `list` shows metadata only.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ACTION="${1:-}"

usage() {
  cat <<'EOF'
Usage:
  scripts/headscale_api_key.sh create
  scripts/headscale_api_key.sh list
  scripts/headscale_api_key.sh expire --prefix <key-prefix>
EOF
}

if [[ -z "$ACTION" ]]; then
  usage
  exit 1
fi

case "$ACTION" in
  create)
    docker compose exec -T headscale headscale apikeys create
    ;;
  list)
    docker compose exec -T headscale headscale apikeys list
    ;;
  expire)
    shift
    PREFIX=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --prefix) PREFIX="${2:-}"; shift 2 ;;
        *)
          echo "Unknown argument: $1"
          usage
          exit 1
          ;;
      esac
    done

    if [[ -z "$PREFIX" ]]; then
      echo "Missing --prefix"
      usage
      exit 1
    fi

    docker compose exec -T headscale headscale apikeys expire --prefix "$PREFIX"
    ;;
  *)
    echo "Unknown action: $ACTION"
    usage
    exit 1
    ;;
esac

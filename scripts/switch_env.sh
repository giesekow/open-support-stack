#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage:
  scripts/switch_env.sh dev
  scripts/switch_env.sh prod
  scripts/switch_env.sh status
  scripts/switch_env.sh restore

Commands:
  dev      Switch .env to .env (no-op, for symmetry)
  prod     Switch .env to .env.production (creates backup first)
  status   Show current .env fingerprint + available env files
  restore  Restore .env from .env.backup
EOF
}

fingerprint() {
  local file="$1"
  if [[ -f "$file" ]]; then
    sha256sum "$file" | awk '{print $1}'
  else
    echo "missing"
  fi
}

cmd="${1:-}"
case "$cmd" in
  dev)
    if [[ ! -f .env ]]; then
      echo "[FAIL] .env is missing"
      exit 1
    fi
    echo "[OK] Using .env (dev)"
    ;;
  prod)
    if [[ ! -f .env.production ]]; then
      echo "[FAIL] .env.production is missing"
      exit 1
    fi
    cp .env .env.backup
    cp .env.production .env
    echo "[OK] Switched .env -> .env.production"
    echo "[INFO] Backup saved as .env.backup"
    ;;
  restore)
    if [[ ! -f .env.backup ]]; then
      echo "[FAIL] .env.backup is missing"
      exit 1
    fi
    cp .env.backup .env
    echo "[OK] Restored .env from .env.backup"
    ;;
  status)
    echo "Current files:"
    for f in .env .env.production .env.backup; do
      if [[ -f "$f" ]]; then
        echo "  - $f: present ($(fingerprint "$f"))"
      else
        echo "  - $f: missing"
      fi
    done
    ;;
  *)
    usage
    exit 1
    ;;
esac


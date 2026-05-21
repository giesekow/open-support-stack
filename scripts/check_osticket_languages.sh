#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> osTicket language pack check"

required=(
  "de.phar:German"
  "fr.phar:French"
  "tr.phar:Turkish"
  "sv_SE.phar:Swedish"
  "nl.phar:Dutch"
)

fail=0

for entry in "${required[@]}"; do
  file="${entry%%:*}"
  name="${entry##*:}"
  if docker compose exec -T osticket sh -lc "test -f /var/www/html/include/i18n/${file}"; then
    echo "[OK] ${name} (${file})"
  else
    echo "[FAIL] ${name} (${file}) is missing"
    fail=$((fail + 1))
  fi
done

if (( fail > 0 )); then
  echo
  echo "Result: ${fail} language pack(s) missing."
  exit 1
fi

echo
echo "All required language packs are present."
echo
echo "Next in osTicket UI:"
echo "1. Admin Panel -> Settings -> System -> Languages"
echo "2. Add/Enable: Deutsch, Francais, Turkce, Svenska, Nederlands"
echo "3. Save changes"

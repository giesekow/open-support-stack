#!/bin/sh
set -eu

mkdir -p /runtime/templates
chown -R support-tools:support-tools /runtime

until su-exec support-tools python -c '
import os
import psycopg
url = os.environ["DATABASE_URL"].replace("postgresql+psycopg://", "postgresql://", 1)
with psycopg.connect(url, connect_timeout=3):
    pass
'; do
  echo "Waiting for support-tools database..."
  sleep 2
done

su-exec support-tools alembic upgrade head
exec su-exec support-tools uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers --forwarded-allow-ips="*"


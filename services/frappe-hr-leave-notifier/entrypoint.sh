#!/bin/sh
set -eu

chown notifier:notifier /data
exec su-exec notifier python /app/notifier.py "$@"

#!/usr/bin/env bash
set -euo pipefail

ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-${MYSQL_ROOT_PASSWORD:-}}"
TIMEOUT="${CONSTRUWX_DB_WAIT_TIMEOUT:-120}"
SLEEP_SECS=2
elapsed=0

if [[ -z "${ROOT_PASSWORD}" ]]; then
  echo "MARIADB_ROOT_PASSWORD (or MYSQL_ROOT_PASSWORD) is required" >&2
  exit 1
fi

echo "Waiting for MariaDB (timeout ${TIMEOUT}s)..."
until mariadb -u root -p"${ROOT_PASSWORD}" -e "SELECT 1" &>/dev/null; do
  if (( elapsed >= TIMEOUT )); then
    echo "MariaDB did not become ready within ${TIMEOUT}s" >&2
    exit 1
  fi
  sleep "${SLEEP_SECS}"
  elapsed=$((elapsed + SLEEP_SECS))
done

echo "MariaDB is ready."

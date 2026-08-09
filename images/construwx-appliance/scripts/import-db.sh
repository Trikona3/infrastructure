#!/usr/bin/env bash
set -euo pipefail

ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-${MYSQL_ROOT_PASSWORD:-}}"
DATABASE="${MARIADB_DATABASE:-${MYSQL_DATABASE:-construwx}}"
IMPORT_FILE="${CONSTRUWX_IMPORT_FILE:-/import/construwx.sql.gz}"
MARKER="${CONSTRUWX_IMPORT_MARKER:-/data/mariadb/.construwx_imported}"

if [[ -z "${ROOT_PASSWORD}" ]]; then
  echo "MARIADB_ROOT_PASSWORD (or MYSQL_ROOT_PASSWORD) is required" >&2
  exit 1
fi

if [[ -f "${MARKER}" ]]; then
  echo "Import already completed (${MARKER}); skipping."
  exit 0
fi

if [[ ! -f "${IMPORT_FILE}" ]]; then
  echo "Import file not found: ${IMPORT_FILE}" >&2
  exit 1
fi

/usr/local/bin/construwx-wait-for-db

echo "Importing ${IMPORT_FILE} into database ${DATABASE}..."
mariadb -u root -p"${ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS \`${DATABASE}\`;"

case "${IMPORT_FILE}" in
  *.gz) zcat "${IMPORT_FILE}" | mariadb -u root -p"${ROOT_PASSWORD}" "${DATABASE}" ;;
  *)    mariadb -u root -p"${ROOT_PASSWORD}" "${DATABASE}" < "${IMPORT_FILE}" ;;
esac

touch "${MARKER}"
chown mysql:mysql "${MARKER}" || true
echo "Import complete."

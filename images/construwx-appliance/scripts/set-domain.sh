#!/usr/bin/env bash
# Detect the site's current hostname/URL from the restored DB, then cut over to WP_DOMAIN.
set -euo pipefail

WP_PATH="${CONSTRUWX_WP_DEST:-/data/wordpress}"
SCHEME="${WP_SCHEME:-https}"
DOMAIN="${WP_DOMAIN:-}"
MARKER="${CONSTRUWX_DOMAIN_MARKER:-/data/wordpress/.construwx_domain_set}"
DATABASE="${MARIADB_DATABASE:-${MYSQL_DATABASE:-construwx}}"
ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-${MYSQL_ROOT_PASSWORD:-}}"
TABLE_PREFIX="${WP_DB_PREFIX:-cnet_}"

if [[ -z "${DOMAIN}" ]]; then
  echo "WP_DOMAIN is required (e.g. mydev.construwx.in)" >&2
  exit 1
fi

DOMAIN="${DOMAIN#https://}"
DOMAIN="${DOMAIN#http://}"
DOMAIN="${DOMAIN%/}"

NEW_URL="${SCHEME}://${DOMAIN}"

if [[ ! -f "${WP_PATH}/wp-config.php" ]]; then
  echo "wp-config.php not found at ${WP_PATH}" >&2
  exit 1
fi

if [[ -f "${MARKER}" ]] && [[ "$(cat "${MARKER}")" == "${NEW_URL}" ]]; then
  echo "Domain already set to ${NEW_URL} (${MARKER}); skipping."
  exit 0
fi

/usr/local/bin/construwx-wait-for-db

cd "${WP_PATH}"

detect_old_siteurl() {
  local url=""
  # Prefer WP-CLI against whatever URL the DB currently expects
  if url="$(wp --allow-root --skip-plugins --skip-themes option get siteurl 2>/dev/null)"; then
    if [[ -n "${url}" ]]; then
      echo "${url}"
      return 0
    fi
  fi

  if [[ -n "${ROOT_PASSWORD}" ]]; then
    url="$(mariadb -N -u root -p"${ROOT_PASSWORD}" "${DATABASE}" \
      -e "SELECT option_value FROM ${TABLE_PREFIX}options WHERE option_name='siteurl' LIMIT 1;" 2>/dev/null || true)"
    if [[ -n "${url}" ]]; then
      echo "${url}"
      return 0
    fi
    url="$(mariadb -N -u root -p"${ROOT_PASSWORD}" "${DATABASE}" \
      -e "SELECT meta_value FROM ${TABLE_PREFIX}sitemeta WHERE meta_key='siteurl' LIMIT 1;" 2>/dev/null || true)"
    if [[ -n "${url}" ]]; then
      echo "${url}"
      return 0
    fi
    local host=""
    host="$(mariadb -N -u root -p"${ROOT_PASSWORD}" "${DATABASE}" \
      -e "SELECT domain FROM ${TABLE_PREFIX}site LIMIT 1;" 2>/dev/null || true)"
    if [[ -n "${host}" ]]; then
      echo "https://${host}"
      return 0
    fi
  fi

  return 1
}

echo "Detecting current site URL from restored database..."
OLD_SITEURL="$(detect_old_siteurl || true)"
if [[ -z "${OLD_SITEURL}" ]]; then
  echo "Could not detect siteurl/home/domain from the database." >&2
  exit 1
fi

OLD_SITEURL="${OLD_SITEURL%/}"
# Strip to scheme://host[:port]
if [[ "${OLD_SITEURL}" =~ ^(https?://[^/]+) ]]; then
  OLD_BASE="${BASH_REMATCH[1]}"
else
  OLD_BASE="${OLD_SITEURL}"
fi

OLD_HOST="${OLD_BASE#http://}"
OLD_HOST="${OLD_HOST#https://}"

echo "Detected old base URL: ${OLD_BASE}"
echo "Detected old host:      ${OLD_HOST}"
echo "Target URL:             ${NEW_URL}"

if [[ "${OLD_HOST}" == "${DOMAIN}" ]] && [[ "${OLD_BASE}" == "${NEW_URL}" ]]; then
  echo "Already on target domain."
  echo "${NEW_URL}" > "${MARKER}"
  exit 0
fi

WP_URL_ARGS=(--allow-root --skip-plugins --skip-themes)
# Use old URL when possible so multisite bootstrap succeeds during replace
if [[ -n "${OLD_BASE}" ]]; then
  WP_URL_ARGS+=(--url="${OLD_BASE}/")
fi

run_wp() {
  wp "${WP_URL_ARGS[@]}" "$@"
}

echo "Running search-replace (serialized-safe)..."
# Full URL variants
for old in \
  "${OLD_BASE}" \
  "http://${OLD_HOST}" \
  "https://${OLD_HOST}"
do
  if [[ "${old}" == "${NEW_URL}" ]]; then
    continue
  fi
  run_wp search-replace "${old}" "${NEW_URL}" --all-tables --precise --recurse-objects --skip-columns=guid --report-changed-only || true
done

# Multisite domain column / host-only references
if [[ "${OLD_HOST}" != "${DOMAIN}" ]]; then
  run_wp search-replace "${OLD_HOST}" "${DOMAIN}" --all-tables --precise --recurse-objects --skip-columns=guid --report-changed-only || true
fi

echo "Updating wp-config constants..."
# Always quote string constants (never --raw for hostnames)
run_wp config set DOMAIN_CURRENT_SITE "${DOMAIN}" --type=constant
run_wp config set WP_HOME "${NEW_URL}" --type=constant
run_wp config set WP_SITEURL "${NEW_URL}" --type=constant
if [[ "${SCHEME}" == "https" ]]; then
  run_wp config set FORCE_SSL_ADMIN true --type=constant --raw
else
  run_wp config set FORCE_SSL_ADMIN false --type=constant --raw
fi

# Ensure options match (main site)
run_wp option update siteurl "${NEW_URL}" || true
run_wp option update home "${NEW_URL}" || true
run_wp network meta update 1 siteurl "${NEW_URL}/" || true

echo "${NEW_URL}" > "${MARKER}"
chown www-data:www-data "${MARKER}" || true

echo "Domain cutover complete: ${OLD_BASE} -> ${NEW_URL}"
echo "Verify with: wp --allow-root --url=${NEW_URL}/ option get siteurl"

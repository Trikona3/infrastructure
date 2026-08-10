#!/usr/bin/env bash
# Sync WordPress core from the image into /data/wordpress.
# Preserves site data: wp-content/, wp-config.php, wp-salt.php, and other local root files.
set -euo pipefail

SRC="${CONSTRUWX_WP_SRC:-/usr/src/wordpress}"
DEST="${CONSTRUWX_WP_DEST:-/data/wordpress}"

if [[ ! -d "${SRC}/wp-admin" || ! -d "${SRC}/wp-includes" ]]; then
  echo "WordPress core source missing at ${SRC}" >&2
  exit 1
fi

mkdir -p "${DEST}"

echo "Ensuring WordPress core in ${DEST} from ${SRC}..."

# Core directories: keep in sync with the image (restores missing files like admin-ajax.php)
rsync -a --delete "${SRC}/wp-admin/" "${DEST}/wp-admin/"
rsync -a --delete "${SRC}/wp-includes/" "${DEST}/wp-includes/"

# Root core files shipped by WordPress (overwrite so index.php / wp-login.php stay correct)
while IFS= read -r -d '' file; do
  base="$(basename "${file}")"
  case "${base}" in
    wp-config.php|wp-config-sample.php)
      continue
      ;;
  esac
  cp -a "${file}" "${DEST}/${base}"
done < <(find "${SRC}" -maxdepth 1 -type f -print0)

# Never clobber site config/secrets if present; only seed sample when absent
if [[ ! -f "${DEST}/wp-config.php" && -f "${SRC}/wp-config-sample.php" ]]; then
  cp -a "${SRC}/wp-config-sample.php" "${DEST}/wp-config-sample.php"
fi

mkdir -p "${DEST}/wp-content/uploads" "${DEST}/wp-content/plugins" "${DEST}/wp-content/themes"

# Critical-path sanity check
if [[ ! -f "${DEST}/wp-admin/admin-ajax.php" ]]; then
  echo "FATAL: wp-admin/admin-ajax.php missing after core sync" >&2
  exit 1
fi

echo "WordPress core OK (admin-ajax.php present)."

#!/usr/bin/env bash
#
# backup.sh — daily / weekly / monthly WordPress backup to Backblaze B2
#
# ┌───────── minute
# │ ┌─────── hour
# │ │ ┌───── day-of-month
# │ │ │ ┌─── month
# │ │ │ │ ┌─ day-of-week (0-6 ⇒ Sun-Sat, 7 ⇒ Sun)
# │ │ │ │ │
# │ │ │ │ │
# 0 3 * * *   /opt/backup/backup_wordpress.sh >> /var/log/backup.log 2>&1
#
#   • Runs at 03:00 *server-local* time.
#   • Every run →  B2 prefix **daily/**
#   • Sunday runs → B2 prefix **weekly/**
#   • 1st-of-the-month runs → B2 prefix **monthly/**
#
# One-time B2 bucket lifecycle rules (via web UI or `b2 update-bucket`):
#   keep daily/    14 days
#   keep weekly/  120 days
#   keep monthly/ 400 days
#
# Needs:
#   – Backblaze CLI (`b2`), logged in with a *writeFiles-only* key
#   – curl
#   – xz
#   – .env
#
# Restore test:
#   xz -d <file.sql.xz | mysql …        (DB)
#   xz -d <file.tar.xz | tar -xvf -     (wp-content)
#

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/.env"
backblaze-b2 authorize-account "$B2_APPLICATION_KEY_ID" "$B2_APPLICATION_KEY"
idle() { nice -n 19 ionice -c 3 "$@"; }

STAMP=$(date +%Y%m%d)
BASE="${DOMAIN}-${STAMP}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Database dump (uncompressed copy stays in ./db-dump/)
SEED_SQL="${SCRIPT_DIR}/db-dump/${DOMAIN}.sql"
echo "[$STAMP] Dumping database..."
docker compose exec -T db mariadb-dump \
  --single-transaction \
  -u "$WORDPRESS_DB_USER" \
  -p"$WORDPRESS_DB_PASSWORD" \
  "$WORDPRESS_DB_NAME" > "$SEED_SQL"

SQL_XZ="${TMPDIR}/${BASE}.sql.xz"
echo "Compressing SQL…"
idle xz -T0 -9 "$SEED_SQL" -c > "$SQL_XZ"

CONTENT_XZ="$TMPDIR/${BASE}.tar.xz"
echo "Archiving wp-content…"
idle tar -cJf "$CONTENT_XZ" wp-content

# Decide cadence classes for this run
classes=(daily)
[[ $(date +%u) == 7 ]] && classes+=(weekly)	# Sunday
[[ $(date +%d) == 01 ]] && classes+=(monthly)	# 1st of month

# Upload to B2
echo "Uploading to B2 bucket $B2_BUCKET…"
for c in "${classes[@]}"; do
	backblaze-b2 upload-file --noProgress "$B2_BUCKET" "$SQL_XZ" "${c}/${DOMAIN}/${BASE}.sql.xz"
	backblaze-b2 upload-file --noProgress "$B2_BUCKET" "$CONTENT_XZ" "${c}/${DOMAIN}/${BASE}.tar.xz"
done

echo "Pinging healthcheck…"
curl -fsS -m 10 --retry 5 "$HEALTHCHECK_URL" || echo "Healthcheck ping failed"

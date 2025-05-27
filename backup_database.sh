#!/usr/bin/env bash

set -euo pipefail
source .env

STAMP=$(date +%F-%H%M)
TMP=./db-dump/wordpress.sql           # file MariaDB will look for next time
ARCHIVE=./db-dump/backup-$STAMP.sql.gz

echo "Dumping database…"
docker compose exec -T db mariadb-dump \
	--single-transaction \
	-u $WORDPRESS_DB_USER \
	-p"$WORDPRESS_DB_PASSWORD" \
	"$WORDPRESS_DB_NAME" > "$TMP"

echo "Compressing previous seed (if any)…"
if [ -f "$TMP" ]; then gzip -c "$TMP" > "$ARCHIVE"; fi

echo "Done. Fresh seed is $(du -h "$TMP" | cut -f1)."

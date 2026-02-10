#!/bin/sh
#
# tune.sh — generate PHP-FPM and MariaDB configs based on system RAM
#
# Run once after cloning, or again if the instance is resized.
# Writes:
#   conf/php/fpm.conf
#   conf/mariadb/50-memory.cnf
#

set -eu
cd "$(dirname "$0")"

RAM_MB=$(free -m | awk '/^Mem:/ {print $2}')

# MariaDB: 25% of RAM for buffer pool
BUFFER_POOL=$((RAM_MB / 4))

# FPM: (RAM - OS/httpd overhead - MariaDB) / 50MB per child, capped 4–16
DB_OVERHEAD=$((BUFFER_POOL + 100))
AVAILABLE=$((RAM_MB - 180 - DB_OVERHEAD))
MAX_CHILDREN=$((AVAILABLE / 50))
MAX_CHILDREN=$((MAX_CHILDREN < 4  ? 4  : MAX_CHILDREN))
MAX_CHILDREN=$((MAX_CHILDREN > 16 ? 16 : MAX_CHILDREN))

START=$((MAX_CHILDREN / 4))
START=$((START < 1 ? 1 : START))
MAX_SPARE=$((MAX_CHILDREN / 2))
MAX_SPARE=$((MAX_SPARE < 2 ? 2 : MAX_SPARE))

# max_connections = one per FPM child + headroom for admin/backup
MAX_CONN=$((MAX_CHILDREN + 5))

echo "System RAM:          ${RAM_MB}MB"
echo "buffer_pool_size:    ${BUFFER_POOL}M"
echo "max_connections:     ${MAX_CONN}"
echo "pm.max_children:     ${MAX_CHILDREN}"
echo "pm.start_servers:    ${START}"
echo "pm.min_spare_servers: 2"
echo "pm.max_spare_servers: ${MAX_SPARE}"
echo "pm.max_requests:     500"

cat > conf/mariadb/50-memory.cnf <<EOF
[mariadb]
innodb_buffer_pool_size = ${BUFFER_POOL}M
max_connections = ${MAX_CONN}
EOF

cat > conf/php/fpm.conf <<EOF
[www]
pm.max_children = ${MAX_CHILDREN}
pm.start_servers = ${START}
pm.min_spare_servers = 2
pm.max_spare_servers = ${MAX_SPARE}
pm.max_requests = 500
EOF

echo "Wrote conf/mariadb/50-memory.cnf and conf/php/fpm.conf"

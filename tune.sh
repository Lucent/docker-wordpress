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

# ── Memory budget ────────────────────────────────────────────────
# Goal: worst-case total fits in 90% of RAM (10% left for page cache).
#
#   Component               Budget
#   ─────────────────────────────────────────────
#   OS + httpd + Docker      200 MB  (fixed)
#   InnoDB buffer pool       RAM / 4
#   DB global buffers         80 MB  (key 8 + aria 8 + log 16 + misc)
#   DB per-connection          2 MB  × max_connections
#   PHP-FPM children          50 MB  × max_children
#
# max_connections = max_children + 5  (admin/backup headroom)
#
# Solving for max_children (C):
#   USABLE = RAM × 0.9
#   USABLE = 200 + BP + 80 + (C+5)×2 + C×50
#        C = (USABLE - 200 - BP - 80 - 10) / 52

RESERVE=200
DB_GLOBAL_OTHER=80
PER_CONN_MB=2
ADMIN_CONNS=5
CHILD_MB=50

# MariaDB: 25% of RAM for InnoDB buffer pool
BUFFER_POOL=$((RAM_MB / 4))

USABLE=$((RAM_MB * 9 / 10))
FIXED=$((RESERVE + BUFFER_POOL + DB_GLOBAL_OTHER + ADMIN_CONNS * PER_CONN_MB))

MAX_CHILDREN=$(( (USABLE - FIXED) / (CHILD_MB + PER_CONN_MB) ))
MAX_CHILDREN=$((MAX_CHILDREN < 4  ? 4  : MAX_CHILDREN))
MAX_CHILDREN=$((MAX_CHILDREN > 16 ? 16 : MAX_CHILDREN))

START=$((MAX_CHILDREN / 4))
START=$((START < 1 ? 1 : START))
MAX_SPARE=$((MAX_CHILDREN / 2))
MAX_SPARE=$((MAX_SPARE < 2 ? 2 : MAX_SPARE))

MAX_CONN=$((MAX_CHILDREN + ADMIN_CONNS))

TOTAL=$((RESERVE + BUFFER_POOL + DB_GLOBAL_OTHER + MAX_CONN * PER_CONN_MB + MAX_CHILDREN * CHILD_MB))
PCT=$((TOTAL * 100 / RAM_MB))

echo "System RAM:            ${RAM_MB} MB"
echo ""
echo "MariaDB:"
echo "  buffer_pool_size:    ${BUFFER_POOL} MB"
echo "  max_connections:     ${MAX_CONN}"
echo ""
echo "PHP-FPM:"
echo "  pm.max_children:     ${MAX_CHILDREN}"
echo "  pm.start_servers:    ${START}"
echo "  pm.min_spare_servers: 2"
echo "  pm.max_spare_servers: ${MAX_SPARE}"
echo "  pm.max_requests:     500"
echo ""
echo "Memory budget:         ${TOTAL} / ${RAM_MB} MB (${PCT}%)"

cat > conf/mariadb/50-memory.cnf <<EOF
[mariadb]
# ── Global buffers ──
innodb_buffer_pool_size = ${BUFFER_POOL}M
key_buffer_size         = 8M
aria_pagecache_buffer_size = 8M
innodb_log_buffer_size  = 16M

# ── Per-connection buffers ──
sort_buffer_size        = 512K
join_buffer_size        = 256K
read_buffer_size        = 128K
read_rnd_buffer_size    = 128K
max_allowed_packet      = 64M

# ── Connections ──
max_connections         = ${MAX_CONN}
thread_cache_size       = ${MAX_CONN}

# ── Table cache ──
table_open_cache        = 400
table_definition_cache  = 256

# ── InnoDB performance ──
innodb_flush_log_at_trx_commit = 2
innodb_flush_method            = O_DIRECT
innodb_log_file_size           = 64M

# ── Disable unused features ──
performance_schema = OFF

# ── Network ──
skip_name_resolve = ON
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

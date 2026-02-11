# Docker WordPress — Architecture Overview

Containers are disposable. All state lives on the host.

## Architecture

Three containers orchestrated via `docker-compose.yml`:

| Service | Image | Role |
|---------|-------|------|
| **httpd** | Custom build from `httpd:alpine` | Apache event MPM — serves static files, proxies PHP to FPM |
| **wordpress** | `wordpress:fpm-alpine` | PHP-FPM — handles only `.php` requests |
| **db** | `mariadb:11` | MariaDB database |

The Dockerfile enables `ssl`, `md`, `proxy_fcgi`, and `rewrite` modules on the stock `httpd:alpine` image. WordPress core files live in a shared named volume (`wordpress_files`) populated by the FPM entrypoint; httpd reads them to serve static assets without invoking PHP.

## Fresh Deploy

```bash
# Clone and configure
git clone <repo-url> docker-wordpress
cd docker-wordpress
cp .env.template .env
# Edit .env — set DOMAIN, WORDPRESS_DB_PASSWORD, B2 keys, healthcheck URL

# Tune for this machine's RAM (writes conf/php/fpm.conf and conf/mariadb/50-memory.cnf)
./tune.sh

# Seed WP Super Cache config (skipped if wp-content already has one)
cp -n conf/wp-super-cache/wp-cache-config.php wp-content/

# Restore data (skip for a brand-new site)
# Place SQL dump:     db-dump/<domain>.sql
# Extract wp-content: tar -xf wp-content-backup.tar

# Start
docker compose up -d --build

# Set up cron (backup + daily graceful reload for mod_md cert activation)
crontab -e
# 0 3 * * *  /root/docker-wordpress/backup.sh >> /var/log/backup-wordpress.log 2>&1
# 0 4 * * *  docker compose -f /root/docker-wordpress/docker-compose.yml exec -T httpd apachectl graceful >> /var/log/apache-reload.log 2>&1
```

## Upgrading an Existing Instance

```bash
cd docker-wordpress

# Back up first
./backup.sh

# Pull the latest changes
git pull

# Re-tune (in case tune.sh formula changed, or instance was resized)
./tune.sh

# Rebuild and restart (--build picks up Dockerfile changes)
docker compose up -d --build
```

## Destructible Design

Everything stateful lives on the host via bind mounts, so containers can be destroyed and recreated at will:

| Host Path | Container(s) | Container Path | Purpose |
|-----------|-------------|---------------|---------|
| `./wp-content` | httpd (ro), wordpress | `/var/www/html/wp-content` | Plugins, themes, uploads |
| `./certs` | httpd | `/var/lib/apache-md` | Let's Encrypt certs (auto-renewed by mod_md) |
| `./conf/mariadb` | db (ro) | `/etc/mysql/conf.d` | DB memory tuning |
| `./conf/php/tweaks.ini` | wordpress (ro) | `/usr/local/etc/php/conf.d/tweaks.ini` | PHP upload limits |
| `./conf/php/fpm.conf` | wordpress (ro) | `/usr/local/etc/php-fpm.d/zzz-tuning.conf` | FPM pool tuning |
| `./db-dump` | db | `/docker-entrypoint-initdb.d` | SQL seed on first boot |
| `db_data` (named vol) | db | `/var/lib/mysql` | Live database |
| `wordpress_files` (named vol) | httpd (ro), wordpress | `/var/www/html` | WordPress core files |

The `db-dump/` directory doubles as both the seed for fresh containers and the latest backup target.

## Tuning (`tune.sh`)

Run `./tune.sh` to auto-generate FPM and MariaDB configs based on detected RAM. Re-run after resizing the instance. The script solves for max_children such that worst-case total stays within 90% of RAM (10% reserved for page cache):

| | 1 GB | 2 GB | 4 GB |
|---|---|---|---|
| `innodb_buffer_pool_size` | 256M | 512M | 978M |
| `max_connections` | 12 | 21 | 21 |
| `pm.max_children` | 7 | 16 | 16 |
| `pm.start_servers` | 1 | 4 | 4 |
| `pm.max_spare_servers` | 3 | 8 | 8 |
| `pm.max_requests` | 500 | 500 | 500 |
| **Memory budget** | **~910 MB (89%)** | **~1634 MB (80%)** | **~2100 MB (54%)** |

The MariaDB config also pins defaults that would otherwise waste RAM on a WordPress (InnoDB-only) workload: `key_buffer_size = 8M` (MyISAM unused), `aria_pagecache_buffer_size = 8M`, `sort_buffer_size = 512K`, `innodb_flush_log_at_trx_commit = 2`, `O_DIRECT` to avoid double-buffering, and `skip_name_resolve` / `performance_schema = OFF`.

After running `tune.sh`, restart to apply: `docker compose up -d`

## Backup Strategy (`backup.sh`)

Runs daily at 3 AM via cron, uploading to Backblaze B2 with tiered retention:

- **Daily** — kept 14 days (B2 lifecycle rules)
- **Weekly** (Sundays) — kept 90 days
- **Monthly** (1st) — kept 365 days

Each run dumps the database to `db-dump/<domain>.sql` (uncompressed locally for instant restore), then XZ-compresses both the SQL and `wp-content` (excluding `cache/`) for upload. A Healthchecks.io ping confirms success.

## SSL/TLS

Apache mod_md handles Let's Encrypt certificate issuance and renewal automatically. Port 80 allows ACME challenges then redirects to 443. The `www.` subdomain redirects to the bare domain.

mod_md renews certificates into a staging directory but **does not activate them** until Apache receives a graceful restart. A daily cron job handles this.

## Restore Procedures

```bash
# Full redeploy from backups:
docker compose down -v
xz -d < monthly/wp-content.tar.xz | tar -xvf -
xz -d < monthly/db.sql.xz > db-dump/*.org.sql
docker compose up -d
```

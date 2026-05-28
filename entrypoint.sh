#!/usr/bin/env sh
set -eu

# Ensure we're in the app root
cd /var/www

echo "[entrypoint] APP_ENV=${APP_ENV:-prod}"

# Fix permissions for var directory (important when mounted as volume)
echo "[entrypoint] Fixing permissions for var directory..."
mkdir -p var/cache var/log var/sessions
chown -R www-data:www-data var
chmod -R 775 var

# Wait for database to be ready and run migrations (max 120 seconds)
if [ "${RUN_MIGRATIONS:-1}" = "1" ]; then
  echo "[entrypoint] Waiting for database to be ready..."

  DB_HOST=""
  DB_PORT="3306"

  if [ -z "${DATABASE_URL:-}" ]; then
    echo "[entrypoint] ⚠️  DATABASE_URL is not set"
    DB_HOST="${MYSQL_HOST:-}"
    DB_PORT="${MYSQL_PORT:-3306}"
    if [ -z "$DB_HOST" ]; then
      echo "[entrypoint] ❌ Neither DATABASE_URL nor MYSQL_HOST are set — skipping migrations"
    else
      echo "[entrypoint] Using MYSQL_HOST fallback — Host: $DB_HOST, Port: $DB_PORT"
    fi
  else
    DB_HOST=$(echo "$DATABASE_URL" | sed -n 's|.*@\([^:/]*\).*|\1|p')
    DB_PORT=$(echo "$DATABASE_URL" | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
    DB_PORT="${DB_PORT:-3306}"
    echo "[entrypoint] ✅ DATABASE_URL parsed — Host: $DB_HOST, Port: $DB_PORT"
  fi

  if [ -n "$DB_HOST" ]; then
    DB_READY=0
    MAX_ATTEMPTS=120
    ATTEMPT=0

    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
      if timeout 2 bash -c "echo > /dev/tcp/$DB_HOST/$DB_PORT" 2>/dev/null; then
        echo "[entrypoint] ✅ Database is ready!"
        DB_READY=1
        break
      fi
      ATTEMPT=$((ATTEMPT + 1))
      if [ $((ATTEMPT % 10)) -eq 0 ]; then
        echo "[entrypoint] ⏳ Still waiting for database... (${ATTEMPT}s / ${MAX_ATTEMPTS}s)"
      fi
      sleep 1
    done

    if [ $DB_READY -eq 1 ]; then
      echo "[entrypoint] Running Doctrine migrations..."
      php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration || true
    else
      echo "[entrypoint] ⚠️  Database not reachable after ${MAX_ATTEMPTS}s — skipping migrations"
    fi
  fi
fi

# Render nginx config from template so it binds to $PORT (Railway sets PORT)
if [ -f /etc/nginx/nginx.conf.template ]; then
  echo "[entrypoint] Rendering /etc/nginx/nginx.conf from template (PORT=${PORT:-80})"
  envsubst '$PORT' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf || true
fi

echo "[entrypoint] ✅ Application ready — starting supervisord"
exec "$@"


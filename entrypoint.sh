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

# Wait for database to be ready (max 120 seconds)
if [ "${RUN_MIGRATIONS:-1}" = "1" ]; then
  echo "[entrypoint] Waiting for database to be ready..."
  
  # Extract host and port from DATABASE_URL if available
  if [ -n "${DATABASE_URL:-}" ]; then
    # Parse DATABASE_URL: mysql://user:pass@host:port/db
    DB_HOST=$(echo "$DATABASE_URL" | sed -n 's|.*@\([^:]*\).*|\1|p')
    DB_PORT=$(echo "$DATABASE_URL" | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
    DB_PORT="${DB_PORT:-3306}"
    echo "[entrypoint] Using DATABASE_URL - Host: $DB_HOST, Port: $DB_PORT"
  else
    DB_HOST="${MYSQL_HOST:-db}"
    DB_PORT="${MYSQL_PORT:-3306}"
    echo "[entrypoint] Using MYSQL_HOST/MYSQL_PORT - Host: $DB_HOST, Port: $DB_PORT"
  fi
  
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
      echo "[entrypoint] ⏳ Waiting for database... (attempt $ATTEMPT/$MAX_ATTEMPTS - ${ATTEMPT}s elapsed)"
    fi
    sleep 1
  done
  
  if [ $DB_READY -eq 1 ]; then
    echo "[entrypoint] Running Doctrine migrations..."
    php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration
  else
    echo "[entrypoint] ❌ Database failed to be ready after 120 seconds"
    echo "[entrypoint] DB_HOST=$DB_HOST, DB_PORT=$DB_PORT"
    echo "[entrypoint] DATABASE_URL=${DATABASE_URL:-NOT SET}"
    echo "[entrypoint] Skipping migrations - app will start but migrations may be incomplete"
  fi
fi

echo "[entrypoint] Warming Symfony cache..."
php bin/console cache:warmup --no-interaction || true

# Start PHP-FPM (default CMD)
exec "$@"


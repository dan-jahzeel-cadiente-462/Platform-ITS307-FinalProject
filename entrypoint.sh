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

# Wait for database to be ready (max 60 seconds)
if [ "${RUN_MIGRATIONS:-1}" = "1" ]; then
  echo "[entrypoint] Waiting for database to be ready..."
  DB_HOST="${MYSQL_HOST:-db}"
  DB_PORT="${MYSQL_PORT:-3306}"
  DB_READY=0
  MAX_ATTEMPTS=60
  ATTEMPT=0
  
  while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if timeout 2 bash -c "echo > /dev/tcp/$DB_HOST/$DB_PORT" 2>/dev/null; then
      echo "[entrypoint] Database is ready!"
      DB_READY=1
      break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    if [ $((ATTEMPT % 5)) -eq 0 ]; then
      echo "[entrypoint] Waiting for database... (attempt $ATTEMPT/$MAX_ATTEMPTS)"
    fi
    sleep 1
  done
  
  if [ $DB_READY -eq 1 ]; then
    echo "[entrypoint] Running Doctrine migrations..."
    php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration
  else
    echo "[entrypoint] Database failed to be ready after 60 seconds, skipping migrations"
  fi
fi

echo "[entrypoint] Warming Symfony cache..."
php bin/console cache:warmup --no-interaction || true

# Start PHP-FPM (default CMD)
exec "$@"


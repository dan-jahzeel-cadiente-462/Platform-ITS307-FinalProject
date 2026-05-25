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
  
  # Check if DATABASE_URL is available (set by Railway MySQL plugin or manually)
  if [ -z "${DATABASE_URL:-}" ]; then
    echo "[entrypoint] ⚠️  DATABASE_URL is not set"
    echo "[entrypoint] On Railway: Add MySQL service and ensure DATABASE_URL variable is linked"
    echo "[entrypoint] Checking if MYSQL_HOST is available for fallback (local development)..."
    
    # For local development with docker-compose, try MYSQL_HOST
    DB_HOST="${MYSQL_HOST:-}"
    DB_PORT="${MYSQL_PORT:-}"
    
    if [ -z "$DB_HOST" ]; then
      echo "[entrypoint] ❌ Neither DATABASE_URL nor MYSQL_HOST are set!"
      echo "[entrypoint] Skipping migrations - database connection information missing"
      echo "[entrypoint] To fix:"
      echo "[entrypoint]   - Railway: Add MySQL service and redeploy"
      echo "[entrypoint]   - Local: Ensure docker-compose.yaml has 'env_file: .env' and db service is named 'db'"
    else
      echo "[entrypoint] Using fallback MYSQL_HOST - Host: $DB_HOST, Port: ${DB_PORT:-3306}"
      DB_PORT="${DB_PORT:-3306}"
    fi
  else
    # Parse DATABASE_URL: mysql://user:pass@host:port/db
    echo "[entrypoint] DATABASE_URL is set, parsing connection details..."
    DB_HOST=$(echo "$DATABASE_URL" | sed -n 's|.*@\([^:]*\).*|\1|p')
    DB_PORT=$(echo "$DATABASE_URL" | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
    DB_PORT="${DB_PORT:-3306}"
    echo "[entrypoint] ✅ Using DATABASE_URL - Host: $DB_HOST, Port: $DB_PORT"
  fi
  
  # Only attempt database connection if we have a host
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
        echo "[entrypoint] ⏳ Waiting for database... (attempt $ATTEMPT/$MAX_ATTEMPTS - ${ATTEMPT}s elapsed)"
      fi
      sleep 1
    done
    
    if [ $DB_READY -eq 1 ]; then
      echo "[entrypoint] Running Doctrine migrations..."
      php bin/console doctrine:migrations:migrate --no-interaction --allow-no-migration || true
    else
      echo "[entrypoint] ⚠️  Database failed to connect after 120 seconds at $DB_HOST:$DB_PORT"
      echo "[entrypoint] Skipping migrations - app will start but database may not be available"
    fi
  fi
fi

echo "[entrypoint] Warming Symfony cache..."
php bin/console cache:warmup --no-interaction || true

# Start PHP-FPM (default CMD)
exec "$@"


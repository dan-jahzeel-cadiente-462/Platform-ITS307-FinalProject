#!/usr/bin/env sh
set -eu

# Ensure we're in the app root
cd /var/www

echo "[entrypoint] ========================================"
echo "[entrypoint] Symfony Application Startup"
echo "[entrypoint] APP_ENV=${APP_ENV:-prod}"
echo "[entrypoint] ========================================"

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
    # Parse DATABASE_URL: mysql://user:pass@host:port/db
    echo "[entrypoint] DATABASE_URL is set, parsing connection details..."
    # Extract host and port using sed
    if echo "$DATABASE_URL" | grep -q '@'; then
      DB_HOST=$(echo "$DATABASE_URL" | sed 's|.*@\([^:/]*\).*|\1|')
      # Extract port if present, otherwise default to 3306
      DB_PORT=$(echo "$DATABASE_URL" | grep -oE ':[0-9]+/' | tr -d ':/' || echo "3306")
      if [ -n "$DB_HOST" ]; then
        echo "[entrypoint] ✅ DATABASE_URL parsed — Host: $DB_HOST, Port: $DB_PORT"
      else
        echo "[entrypoint] ⚠️  Could not parse DATABASE_URL host!"
        DB_HOST=""
      fi
    else
      echo "[entrypoint] ⚠️  DATABASE_URL format invalid (expected mysql://user:pass@host:port/db)"
      DB_HOST=""
    fi
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
  # Ensure PORT has a default value so envsubst can substitute it
  PORT="${PORT:-80}"
  # Validate PORT is not empty
  if [ -z "$PORT" ]; then
    echo "[entrypoint] ❌ CRITICAL: PORT is empty after default assignment!"
    exit 1
  fi
  export PORT
  echo "[entrypoint] Rendering /etc/nginx/nginx.conf from template (PORT=$PORT)"
  if ! envsubst '$PORT' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf; then
    echo "[entrypoint] ❌ CRITICAL: envsubst failed to render nginx config!"
    exit 1
  fi
  # Verify the config was rendered correctly (check for unsubstituted variables)
  if grep -q '${PORT' /etc/nginx/nginx.conf; then
    echo "[entrypoint] ❌ CRITICAL: nginx config still contains unsubstituted \${PORT} variables!"
    cat /etc/nginx/nginx.conf | grep -E '\${PORT|listen'
    exit 1
  fi
  echo "[entrypoint] ✅ Nginx config rendered successfully with PORT=$PORT"
fi

echo "[entrypoint] Warming Symfony cache for faster first requests..."
php bin/console cache:warmup --no-interaction --env=prod || {
  echo "[entrypoint] ⚠️  Cache warmup failed (non-critical), continuing..."
}

echo "[entrypoint] Applying final ownership and permissions..."
chown -R www-data:www-data /var/www || true
chown -R www-data:www-data /var/log/nginx || true
find /var/www -type d -exec chmod 755 {} + || true
find /var/www -type f -exec chmod 644 {} + || true
chmod 755 /var/www/bin/console || true
chmod -R 775 /var/www/var || true

echo "[entrypoint] ✅ Application ready — starting supervisord"
echo "[entrypoint] Nginx will listen on port $PORT"
echo "[entrypoint] PHP-FPM listening on 127.0.0.1:9000"
echo "[entrypoint] ============================================"

exec "$@"

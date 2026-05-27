# Deployment Fixes for Railway
## Issues Fixed

### Root Cause
The application was failing because only PHP-FPM was running on Railway. Nginx (the HTTP server) was not starting, so requests had no HTTP server to connect to. The local setup used `docker-compose.yaml` to run Nginx in a separate container, but Railway deploys as a single container without docker-compose support.

### Changes Made

1. **supervisord.conf** - New Supervisor configuration to manage both Nginx and PHP-FPM processes in a single container
2. **nginx-supervisord.conf** - Standalone Nginx configuration that works without separate compose files
3. **Dockerfile** - Updated to:
   - Copy supervisord.conf and nginx-supervisord.conf
   - Set `EXPOSE 80` for HTTP traffic
   - Use supervisord as the main process instead of just php-fpm
   - Properly set permissions for nginx to read application code
4. **entrypoint.sh** - Updated to:
   - Set nginx ownership and file permissions
   - Start supervisord instead of just PHP-FPM
5. **docker-compose.yaml** - Updated to mount the full app volume for local development
6. **nginx-main.conf** - Changed `fastcgi_pass php:9000` to `fastcgi_pass 127.0.0.1:9000` (localhost)
7. **Procfile** - Created for explicit Railway process definition

## How It Works Now

### On Railway (Production)
1. Docker builds the image from Dockerfile
2. Container starts and runs entrypoint.sh
3. entrypoint.sh runs migrations and warms cache
4. supervisord starts (as CMD in Dockerfile)
5. supervisord manages both:
   - nginx: HTTP server listening on port 80
   - php-fpm: Application server listening on port 9000
6. Requests: Client → Nginx (port 80) → PHP-FPM → Application

### Locally (docker-compose)
1. Two separate services: `web` (nginx) and `php` (app)
2. Nginx explicitly runs `php-fpm -F` as the command
3. Nginx and PHP communicate over the `appnet` network bridge
4. Port 8080 is mapped to container port 80
5. Works exactly as before

## Deployment Steps

1. **Push to GitHub**
   ```bash
   git add .
   git commit -m "Fix: Add supervisord configuration for Railway deployment"
   git push origin main
   ```

2. **Railway Redeploy**
   - Go to Railway dashboard
   - Your service should automatically redeploy (or trigger manually)
   - Monitor the deployment logs

3. **Verify**
   - Check deployment logs for: "supervisord started"
   - Access your domain - should now show your Symfony app home page
   - Check Railway logs for any errors

## Troubleshooting

If the domain still shows errors:

### 1. Check Rails Logs
- In Railway dashboard, click your service → View Logs
- Look for `supervisord` startup messages
- Look for nginx or php-fpm error messages

### 2. Verify Database Connection
- Check if MySQL service is properly linked (should see `mysql.railway.internal` in logs)
- Run migrations successfully

### 3. Verify Port Binding
- Check that Nginx is listening on port 80
- Railway automatically detects port 80 as the web port

### 4. Clear Cache
- Railway rebuilds automatically, but if you see stale code:
  - Delete the old deployment
  - Redeploy fresh

## Local Testing

```bash
# Build and test locally
docker-compose down
docker-compose build
docker-compose up

# Access at http://localhost:8080
# Check logs: docker-compose logs web
# Check php logs: docker-compose logs php
```

## Files Summary

- **supervisord.conf** - Process manager config (Nginx + PHP-FPM)
- **nginx-supervisord.conf** - Nginx HTTP server config (for Railway single container)
- **nginx-main.conf** - Nginx server block config (shared between both setups)
- **Dockerfile** - Updated to use supervisord in production
- **entrypoint.sh** - Updated to set permissions and start supervisord
- **docker-compose.yaml** - Updated with full volume mount for local dev
- **Procfile** - Optional: Explicit process declaration for Railway

## Why This Works

The key insight is that Railway (and most cloud platforms) expect a single Docker container that listens on port 80. The traditional `docker-compose` setup separates concerns into multiple containers, but in production you need everything in one container. Supervisord is the perfect tool for this - it's a lightweight process manager that runs multiple processes within a single container.


# syntax=docker/dockerfile:1

FROM php:8.3-fpm-alpine AS base

ENV COMPOSER_ALLOW_SUPERUSER=1

# Install system deps for common Symfony + Doctrine usage
RUN apk add --no-cache \
    bash \
    git \
    mysql-client \
    nginx \
    supervisor \
    gettext \
    curl \
    && docker-php-ext-install pdo pdo_mysql opcache

# Install Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www

# Copy only composer manifests first for better build caching
COPY composer.json composer.lock symfony.lock ./

RUN composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader --ignore-platform-reqs --no-scripts

# Copy app source
COPY . .

# Regenerate autoloader so symfony/runtime plugin fires post-autoload-dump
# and produces vendor/autoload_runtime.php (skipped by --no-scripts above)
RUN composer dump-autoload --no-dev --optimize --no-interaction

# Run composer scripts now that app code is present
RUN composer run-script post-install-cmd || true

# Ensure entrypoint is executable
RUN chmod +x /var/www/entrypoint.sh

# Ensure permissions for cache/log directories
RUN mkdir -p var/cache var/log \
    && chown -R www-data:www-data var

# Create nginx log directory and ensure correct ownership
RUN mkdir -p /var/log/nginx && chown -R www-data:www-data /var/log/nginx /var/lib/nginx

# Modify PHP-FPM configuration to listen on local TCP port
RUN sed -i 's/^listen = .*/listen = 127.0.0.1:9000/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/^user = .*/user = www-data/' /usr/local/etc/php-fpm.d/www.conf && \
    sed -i 's/^group = .*/group = www-data/' /usr/local/etc/php-fpm.d/www.conf

# Copy configurations
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY nginx-supervisord.conf.template /etc/nginx/nginx.conf.template

# Set production environment defaults
ENV APP_ENV=prod APP_DEBUG=0 PORT=80

# Run supervisord to manage both nginx and php-fpm processes
EXPOSE 80

ENTRYPOINT ["/var/www/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]

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

# Copy Nginx and supervisor configuration
COPY nginx.conf /etc/nginx/nginx.conf
COPY nginx-main.conf /etc/nginx/conf.d/nginx-main.conf
COPY supervisord.conf /etc/supervisord.conf

# Ensure entrypoint is executable
RUN chmod +x /var/www/entrypoint.sh

# Ensure permissions for cache/log directories
RUN mkdir -p var/cache var/log \
    && chown -R www-data:www-data var

# Build-time cache warmup (production)
ENV APP_ENV=prod \
    APP_DEBUG=0

RUN php bin/console cache:clear --no-interaction --env=prod || true \
    && php bin/console cache:warmup --no-interaction --env=prod || true

EXPOSE 80

# Entrypoint runs migrations + cache warmup, then hands off to supervisord
# which starts both PHP-FPM and Nginx inside the single container.
ENTRYPOINT ["/var/www/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]


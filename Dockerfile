FROM dunglas/frankenphp:1-php8.4-bookworm AS base

RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && install-php-extensions intl zip pdo_pgsql

WORKDIR /app

FROM base AS dependencies

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer
COPY . .
RUN rm -rf vendor bootstrap/cache/*.php \
    && mkdir -p \
        storage/app/private \
        storage/app/public \
        storage/framework/cache/data \
        storage/framework/sessions \
        storage/framework/views \
        storage/logs \
        bootstrap/cache \
    && composer install \
        --no-dev \
        --no-interaction \
        --no-progress \
        --no-scripts \
        --prefer-dist \
        --optimize-autoloader \
        --classmap-authoritative

FROM node:24-alpine AS assets

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY resources ./resources
COPY vite.config.js ./
RUN npm run build

FROM base AS runtime

COPY --from=dependencies --chown=www-data:www-data /app /app
COPY --from=assets --chown=www-data:www-data /app/public/build /app/public/build
COPY --chown=www-data:www-data Caddyfile /etc/frankenphp/Caddyfile

RUN rm -rf /app/storage /app/bootstrap/cache \
    && ln -s /tmp/storage /app/storage \
    && ln -s /tmp/bootstrap/cache /app/bootstrap/cache \
    && chown -R www-data:www-data /config/caddy /data/caddy /app

EXPOSE 8080
ENV PORT=8080 \
    APP_ENV=production \
    LOG_CHANNEL=stderr \
    CACHE_STORE=array \
    SESSION_DRIVER=cookie \
    VIEW_COMPILED_PATH=/tmp/storage/framework/views \
    QUEUE_CONNECTION=sync

USER www-data

CMD ["sh", "-c", "mkdir -p /tmp/storage/app/private /tmp/storage/app/public /tmp/storage/framework/cache/data /tmp/storage/framework/sessions /tmp/storage/framework/views /tmp/storage/logs /tmp/bootstrap/cache && chmod -R 777 /tmp/storage /tmp/bootstrap/cache && php artisan package:discover --ansi && exec frankenphp run --config /etc/frankenphp/Caddyfile"]

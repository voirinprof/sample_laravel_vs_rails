FROM php:8.3-cli

RUN apt-get update && apt-get install -y \
    git unzip libpq-dev libzip-dev zip \
    && docker-php-ext-install pdo pdo_mysql pdo_pgsql zip \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /build

RUN composer create-project laravel/laravel . --prefer-dist --no-interaction
RUN php artisan key:generate

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

WORKDIR /var/www
EXPOSE 8000
ENTRYPOINT ["docker-entrypoint.sh"]
CMD bash -c "until php artisan migrate --force; do echo 'DB pas encore prête, retry dans 3s...'; sleep 3; done && php artisan serve --host=0.0.0.0 --port=8000"
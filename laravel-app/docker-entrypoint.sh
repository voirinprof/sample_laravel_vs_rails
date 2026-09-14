#!/bin/bash
set -e

if [ ! -f /var/www/artisan ]; then
    echo "Premier lancement : copie du code généré vers le volume..."
    cp -a /build/. /var/www/
fi

exec "$@"
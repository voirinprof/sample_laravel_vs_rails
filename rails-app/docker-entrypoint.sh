#!/bin/bash
set -e

if [ ! -f /app/bin/rails ]; then
    echo "Premier lancement : copie du code généré vers le volume..."
    cp -a /build/. /app/
    bundle install
fi

exec "$@"
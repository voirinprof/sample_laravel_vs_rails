# Tutoriel : application Laravel « Livres » avec Docker

Ce tutoriel crée une petite application Laravel permettant de lister et d'ajouter des livres.

Toutes les commandes Artisan sont exécutées **dans le conteneur Docker Laravel**. Il n'est pas nécessaire d'installer PHP, Composer ou Artisan sur la machine hôte.

## 1. Préparer l'arborescence

Depuis le dossier du projet :

```bash
cd sample_laravel_vs_rails
mkdir -p laravel-app/src nginx
```

Le dossier `src` est le volume de développement. L'image Docker génère une
application Laravel de base, puis le script d'entrée la copie dans `src` au
premier démarrage. Aucun dossier `overlay` n'est nécessaire.

Arborescence utilisée :

```text
laravel-vs-rails2/
├── docker-compose.yml
├── laravel-app/
│   ├── Dockerfile
│   ├── docker-entrypoint.sh
│   └── src/
└── nginx/
    └── default.conf
```

## 2. Créer Docker Compose

Créer `docker-compose.yml` :

```yaml
services:
  laravel:
    build: ./laravel-app
    ports:
      - "8000:8000"
    volumes:
      - ./laravel-app/src:/var/www
    environment:
      DB_CONNECTION: mysql
      DB_HOST: laravel-db
      DB_PORT: 3306
      DB_DATABASE: laravel_db
      DB_USERNAME: laravel
      DB_PASSWORD: laravel
    depends_on:
      laravel-db:
        condition: service_healthy

  laravel-db:
    image: mysql:8.0
    environment:
      MYSQL_DATABASE: laravel_db
      MYSQL_USER: laravel
      MYSQL_PASSWORD: laravel
      MYSQL_ROOT_PASSWORD: root
    volumes:
      - laravel_db_data:/var/lib/mysql
    healthcheck:
    test: ["CMD", "mysqladmin", "ping", "-h", "127.0.0.1", "-u", "root", "-proot"]
      interval: 5s
      timeout: 5s
      retries: 20

  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - laravel

volumes:
  laravel_db_data:
```

## 3. Créer l'image Laravel

Créer `laravel-app/Dockerfile` :

```dockerfile
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
CMD bash -c "until php artisan migrate --force; do echo 'Base de données non prête, nouvelle tentative dans 3 secondes...'; sleep 3; done && php artisan serve --host=0.0.0.0 --port=8000"
```

Créer `laravel-app/docker-entrypoint.sh` :

```bash
#!/bin/bash
set -e

if [ ! -f /var/www/artisan ]; then
    echo "Premier lancement : copie du code Laravel vers le volume..."
    cp -a /build/. /var/www/
fi

exec "$@"
```

## 4. Configurer Nginx

Nginx publie Laravel sous `/laravel/`, mais retire ce préfixe avant d'envoyer la requête à Laravel. Laravel reçoit donc `/`, `/livres` ou `/livres/create`.

Créer `nginx/default.conf` :

```nginx
server {
    listen 80;
    server_name _;

    location ^~ /laravel/ {
        proxy_pass http://laravel:8000/;
        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-Prefix /laravel;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location = /laravel {
        return 301 /laravel/;
    }
}
```

Les headers `X-Forwarded-Prefix` et `X-Forwarded-Host` permettent à Laravel de
générer des liens comme `/laravel/livres/create`, avec le bon domaine et le
bon port public, même si le serveur est accessible avec une adresse IP ou un
nom de domaine.

## 5. Démarrer les conteneurs

Depuis le dossier contenant `docker-compose.yml` :

```bash
docker compose up -d --build
```

Vérifier l'état des services :

```bash
docker compose ps
```

Lire les logs Laravel :

```bash
docker compose logs -f laravel
```

Si un premier démarrage a été interrompu et que les migrations échouent avec
une table déjà existante, repartir d'une base vierge :

```bash
docker compose down -v
docker compose up -d --build
```

La commande `down -v` supprime le volume MySQL et donc toutes les données de
l'application.

Le serveur Laravel écoute dans le conteneur sur le port `8000`. L'accès public passe par Nginx :

```text
http://localhost/laravel/
```

## 6. Configurer la base de données Laravel

Le fichier `laravel-app/src/.env` est créé lors du premier démarrage. Vérifier ou remplacer les lignes suivantes :

```dotenv
APP_NAME=Laravel
APP_ENV=local
APP_DEBUG=true
APP_URL=http://localhost

DB_CONNECTION=mysql
DB_HOST=laravel-db
DB_PORT=3306
DB_DATABASE=laravel_db
DB_USERNAME=laravel
DB_PASSWORD=laravel
```

Comme les fichiers de `src` sont créés depuis le conteneur, ils peuvent
appartenir à `root` si Docker est lancé avec `sudo`. Pour pouvoir les modifier
dans VS Code :

```bash
sudo chown -R "$USER:$USER" laravel-app/src
```

`APP_URL` est une valeur de secours pour les commandes CLI. Les URLs HTTP sont construites dynamiquement à partir du domaine reçu et du préfixe transmis par Nginx.

Vider le cache de configuration après une modification :

```bash
docker compose exec laravel php artisan config:clear
```

## 7. Créer le modèle et la migration

Créer le modèle `Livre` et sa migration depuis Docker :

```bash
docker compose exec laravel php artisan make:model Livre -m
```

Repérer le fichier créé :

```bash
find laravel-app/src/database/migrations -name '*create_livres_table.php'
```

Dans la migration, mettre :

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('livres', function (Blueprint $table): void {
            $table->id();
            $table->string('titre');
            $table->string('auteur');
            $table->integer('annee_publication');
            $table->text('resume')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('livres');
    }
};
```

Dans `app/Models/Livre.php` :

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;

#[Fillable(['titre', 'auteur', 'annee_publication', 'resume'])]
class Livre extends Model
{
}
```

L'attribut `Fillable` est nécessaire car le contrôleur utilise
`Livre::create($validated)`.

Exécuter la migration dans le conteneur :

```bash
docker compose exec laravel php artisan migrate
```

Vérifier son état :

```bash
docker compose exec laravel php artisan migrate:status
```

## 8. Créer le contrôleur

```bash
docker compose exec laravel php artisan make:controller LivreController
```

Dans `app/Http/Controllers/LivreController.php` :

```php
<?php

namespace App\Http\Controllers;

use App\Models\Livre;
use Illuminate\Http\Request;

class LivreController extends Controller
{
    public function index()
    {
        $livres = Livre::latest()->get();

        return view('livres.index', compact('livres'));
    }

    public function create()
    {
        return view('livres.create');
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'titre' => 'required|string|max:255',
            'auteur' => 'required|string|max:255',
            'annee_publication' => 'required|integer|min:0',
            'resume' => 'nullable|string',
        ]);

        Livre::create($validated);

        return redirect()->route('livres.index')
            ->with('success', 'Livre ajouté avec succès.');
    }
}
```

## 9. Déclarer les routes

Dans `routes/web.php` :

```php
<?php

use App\Http\Controllers\LivreController;
use Illuminate\Support\Facades\Route;

Route::get('/', [LivreController::class, 'index'])->name('home');

Route::resource('livres', LivreController::class)->only([
    'index', 'create', 'store',
]);
```

Afficher les routes depuis Docker :

```bash
docker compose exec laravel php artisan route:list
```

Les routes importantes sont :

| Méthode | URL interne Laravel | URL publique |
|---|---|---|
| GET | `/` | `/laravel/` |
| GET | `/livres` | `/laravel/livres` |
| GET | `/livres/create` | `/laravel/livres/create` |
| POST | `/livres` | `/laravel/livres` |

## 10. Créer les vues Blade

Créer le dossier :

```bash
mkdir -p laravel-app/src/resources/views/livres
```

Créer `resources/views/livres/index.blade.php` :

```blade
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>Livres</title>
</head>
<body>
    <h1>Livres</h1>

    @if (session('success'))
        <p>{{ session('success') }}</p>
    @endif

    <p><a href="{{ route('livres.create') }}">Ajouter un livre</a></p>

    <table>
        <thead>
            <tr>
                <th>Titre</th>
                <th>Auteur</th>
                <th>Année</th>
            </tr>
        </thead>
        <tbody>
            @forelse ($livres as $livre)
                <tr>
                    <td>{{ $livre->titre }}</td>
                    <td>{{ $livre->auteur }}</td>
                    <td>{{ $livre->annee_publication }}</td>
                </tr>
            @empty
                <tr>
                    <td colspan="3">Aucun livre pour le moment.</td>
                </tr>
            @endforelse
        </tbody>
    </table>
</body>
</html>
```

Créer `resources/views/livres/create.blade.php` :

```blade
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>Ajouter un livre</title>
</head>
<body>
    <h1>Ajouter un livre</h1>

    <p><a href="{{ route('livres.index') }}">Retour à la liste</a></p>

    <form method="POST" action="{{ route('livres.store') }}">
        @csrf

        <label for="titre">Titre</label>
        <input id="titre" type="text" name="titre" value="{{ old('titre') }}">
        @error('titre') <div>{{ $message }}</div> @enderror

        <label for="auteur">Auteur</label>
        <input id="auteur" type="text" name="auteur" value="{{ old('auteur') }}">
        @error('auteur') <div>{{ $message }}</div> @enderror

        <label for="annee_publication">Année de publication</label>
        <input id="annee_publication" type="number" name="annee_publication" value="{{ old('annee_publication') }}">
        @error('annee_publication') <div>{{ $message }}</div> @enderror

        <label for="resume">Résumé</label>
        <textarea id="resume" name="resume" rows="4">{{ old('resume') }}</textarea>

        <button type="submit">Enregistrer</button>
    </form>
</body>
</html>
```

## 11. Rendre les URLs compatibles avec `/laravel`

Modifier `app/Providers/AppServiceProvider.php` :

```php
<?php

namespace App\Providers;

use Illuminate\Support\Facades\URL;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        //
    }

    public function boot(): void
    {
        if (! app()->runningInConsole()) {
            $prefix = rtrim((string) request()->header('X-Forwarded-Prefix'), '/');
            $forwardedHost = request()->header('X-Forwarded-Host');
            $host = $forwardedHost ?: request()->getHttpHost();
            $rootUrl = request()->getScheme().'://'.$host.$prefix;

            URL::forceRootUrl($rootUrl);
        }
    }
}
```

Après modification :

```bash
docker compose exec laravel php artisan config:clear
docker compose restart laravel
docker compose restart nginx
```

Cette configuration fonctionne avec `localhost`, une adresse IP ou un nom de domaine. Par exemple, avec une IP `192.0.2.10`, le lien généré sera :

```text
http://192.0.2.10/laravel/livres/create
```

## 12. Tester l'application

Ouvrir :

```text
http://localhost/laravel/
```

Tester les réponses HTTP :

```bash
curl -I http://localhost/laravel/
curl -I http://localhost/laravel/livres/create
```

Vérifier qu'un lien conserve le préfixe :

```bash
curl -sS http://localhost/laravel/ | grep -o 'livres/create'
```

Tester avec un autre hôte, comme une IP :

```bash
curl -sS -H 'Host: 192.0.2.10' http://localhost/laravel/ \
  | grep -o 'http://192.0.2.10/laravel/livres/create'
```

## 13. Commandes Docker utiles

```bash
# Voir les conteneurs
docker compose ps

# Voir les logs Laravel
docker compose logs -f laravel

# Ouvrir un shell dans le conteneur Laravel
docker compose exec laravel bash

# Exécuter Artisan
docker compose exec laravel php artisan <commande>

# Vider les caches Laravel
docker compose exec laravel php artisan optimize:clear

# Refaire les migrations en développement
# Attention : supprime les données de la base.
docker compose exec laravel php artisan migrate:fresh

# Arrêter les conteneurs
docker compose down

# Arrêter les conteneurs et supprimer les données MySQL
# Attention : les livres enregistrés seront supprimés.
docker compose down -v
```

## Résultat attendu

L'application permet de :

1. consulter la liste sur `/laravel/` ou `/laravel/livres` ;
2. ouvrir le formulaire sur `/laravel/livres/create` ;
3. enregistrer un livre avec `POST /laravel/livres` ;
4. revenir automatiquement à la liste après l'enregistrement.

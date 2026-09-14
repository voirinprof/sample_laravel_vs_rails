# Laravel vs Rails : l'exemple « Livres »

Ce dépôt sert à comprendre les différences entre **Laravel** et **Ruby on
Rails** en construisant la même petite application avec les deux frameworks.

L'exemple est volontairement simple : une application « Livres » permet de
consulter une liste de livres et d'en ajouter un nouveau. La logique métier
reste comparable, tandis que les conventions, les outils et la structure du
code diffèrent selon le framework.

## Objectifs

- découvrir le démarrage d'une application Laravel et d'une application Rails ;
- comparer leurs modèles, migrations, contrôleurs, routes et vues ;
- observer deux bases de données utilisées en parallèle : MySQL pour Laravel
	et PostgreSQL pour Rails ;
- exécuter les deux applications avec Docker, sans installer PHP, Composer,
	Ruby ou Rails sur la machine hôte.

## Structure du dépôt

```text
.
├── docker-compose.yml
├── laravel-app/
│   ├── Dockerfile
│   └── src/              # Code Laravel généré et modifié pendant le tutoriel
├── rails-app/
│   ├── Dockerfile
│   └── src/              # Code Rails généré et modifié pendant le tutoriel
├── nginx/
│   └── default.conf      # Préfixes publics /laravel et /rails
├── TUTORIEL_LARAVEL_LIVRES.md
└── TUTORIEL_RAILS_LIVRES.md
```

## Démarrer le projet

Prérequis : Docker et Docker Compose v2.

Depuis la racine du dépôt :

```bash
docker compose up -d --build
docker compose ps
```

Les applications sont accessibles via Nginx :

| Application | URL publique | Port direct de développement |
| --- | --- | --- |
| Laravel | [http://localhost/laravel/](http://localhost/laravel/) | `8000` |
| Rails | [http://localhost/rails/](http://localhost/rails/) | `3000` |

Nginx retire le préfixe public avant de transmettre la requête à l'application
et le transmet à nouveau lors de la génération des liens. Les URLs restent
donc cohérentes avec `/laravel` ou `/rails`.

Pour consulter les logs :

```bash
docker compose logs -f laravel
docker compose logs -f rails
```

Si Docker doit être lancé avec `sudo`, les fichiers copiés dans `src` peuvent
appartenir à `root`. Pour les modifier dans VS Code :

```bash
sudo chown -R "$USER:$USER" laravel-app/src rails-app/src
```

## Parcours recommandé

1. Lire le tutoriel [Laravel Livres](TUTORIEL_LARAVEL_LIVRES.md).
2. Réaliser le même exemple avec le tutoriel [Rails Livres](TUTORIEL_RAILS_LIVRES.md).
3. Comparer les fichiers et les commandes utilisés par chaque framework.

Les tutoriels expliquent les étapes en détail : génération de l'application,
configuration de la base de données, migration, modèle, contrôleur, routes,
vues et test de l'ajout d'un livre.

## Même logique, deux approches

Dans les deux applications, le parcours fonctionnel est le même :

1. définir une table `livres` avec un titre, un auteur, une année et un résumé ;
2. représenter cette table par un modèle `Livre` ;
3. afficher les livres sur la page d'accueil ;
4. afficher un formulaire de création ;
5. valider les données reçues ;
6. enregistrer le livre en base de données ;
7. revenir à la liste après l'enregistrement.

La comparaison porte donc sur la manière de réaliser cette logique :

| Besoin | Laravel | Rails |
| --- | --- | --- |
| Modèle | Eloquent `App\\Models\\Livre` | Active Record `Livre` |
| Migration | `php artisan make:model Livre -m` | `bin/rails generate model Livre ...` |
| Contrôleur | `LivreController` | `LivresController` |
| Routes | `Route::resource(...)` | `resources :livres` |
| Vues | Blade, dans `resources/views` | ERB, dans `app/views` |
| Validation | `$request->validate(...)` | `validates ...` dans le modèle |
| Base de données | MySQL | PostgreSQL |
| Commandes principales | Artisan | `bin/rails` |

Laravel et Rails proposent tous deux une architecture MVC et un ORM intégré.
La différence se remarque surtout dans les conventions de nommage, les
commandes génératrices, la déclaration des routes et la façon d'exprimer les
validations et les vues.

## Arrêter et réinitialiser

Arrêter les conteneurs en conservant les bases :

```bash
docker compose down
```

Supprimer également les volumes de bases de données :

```bash
docker compose down -v
```

La seconde commande supprime les livres et toutes les données persistées.
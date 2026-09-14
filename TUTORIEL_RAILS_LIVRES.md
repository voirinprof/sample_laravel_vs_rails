# Tutoriel : application Rails « Livres » avec Docker

Ce tutoriel reproduit la même application que le tutoriel Laravel : une liste de livres et un formulaire d'ajout avec les champs `titre`, `auteur`, `annee_publication` et `resume`.

La comparaison est volontairement directe :

| Besoin | Laravel | Rails |
|---|---|---|
| Framework | Laravel | Ruby on Rails |
| ORM | Eloquent | Active Record |
| Base | MySQL | PostgreSQL |
| Générateur | `php artisan make:*` | `bin/rails generate` |
| Migration | `php artisan migrate` | `bin/rails db:migrate` |
| Vue | Blade | ERB |
| Routes | `routes/web.php` | `config/routes.rb` |
| Contrôleur | `app/Http/Controllers` | `app/controllers` |
| Modèle | `app/Models` | `app/models` |

Toutes les commandes Rails sont exécutées **dans le conteneur Docker Rails**. Ruby, Bundler et Rails ne sont pas nécessaires sur la machine hôte.

## 1. Préparer l'arborescence

Depuis le dossier parent :

```bash
cd laravel-vs-rails2
mkdir -p rails-app/src nginx
```

Arborescence utilisée :

```text
laravel-vs-rails2/
├── docker-compose.yml
├── rails-app/
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
  rails:
    build: ./rails-app
    ports:
      - "3000:3000"
    volumes:
      - ./rails-app/src:/app
    environment:
      DATABASE_URL: postgres://rails:rails@rails-db:5432/rails_db
      RAILS_ENV: development
      RAILS_RELATIVE_URL_ROOT: /rails
      SECRET_KEY_BASE: dev_secret_key_base_change_me
    depends_on:
      rails-db:
        condition: service_healthy

  rails-db:
    image: postgres:16
    environment:
      POSTGRES_DB: rails_db
      POSTGRES_USER: rails
      POSTGRES_PASSWORD: rails
    volumes:
      - rails_db_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U rails -d rails_db"]
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
      - rails

volumes:
  rails_db_data:
```

`DATABASE_URL` utilise le nom de service Docker `rails-db`, pas `localhost`. Dans un conteneur, `localhost` désigne le conteneur Rails lui-même.

## 3. Créer l'image Rails

Créer `rails-app/Dockerfile` :

```dockerfile
FROM ruby:3.3

RUN apt-get update -qq && apt-get install -y \
    nodejs postgresql-client \
    && rm -rf /var/lib/apt/lists/*

RUN gem install rails -v 7.1.3

WORKDIR /build

RUN rails new . --database=postgresql --skip-test --skip-jbuilder
RUN bundle install

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

WORKDIR /app
EXPOSE 3000
ENTRYPOINT ["docker-entrypoint.sh"]
CMD bash -c "until bin/rails db:prepare; do echo 'Base de données non prête, nouvelle tentative dans 3 secondes...'; sleep 3; done && bin/rails server -b 0.0.0.0"
```

Créer `rails-app/docker-entrypoint.sh` :

```bash
#!/bin/bash
set -e

if [ ! -f /app/bin/rails ]; then
    echo "Premier lancement : copie du code Rails vers le volume..."
    cp -a /build/. /app/
    bundle install
fi

exec "$@"
```

## 4. Configurer Nginx

Nginx publie Rails sous `/rails/`, mais retire le préfixe avant de transmettre la requête à Rails. Rails reçoit donc `/`, `/livres` ou `/livres/new`.

Créer `nginx/default.conf` :

```nginx
server {
    listen 80;
    server_name _;

    location ^~ /rails/ {
        proxy_pass http://rails:3000/;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Prefix /rails;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location = /rails {
        return 301 /rails/;
    }
}
```

Le slash final dans `proxy_pass http://rails:3000/` retire `/rails` avant l'envoi. Le header `X-Forwarded-Prefix` sert à reconstruire les URLs publiques dans les helpers Rails.

## 5. Démarrer les conteneurs

```bash
docker compose up -d --build
```

Vérifier les services :

```bash
docker compose ps
```

Voir les logs Rails :

```bash
docker compose logs -f rails
```

L'accès public se fera via :

```text
http://localhost/rails/
```

## 6. Vérifier la connexion PostgreSQL

Le fichier `config/database.yml` généré par Rails peut rester standard : `DATABASE_URL` fourni par Docker prend en charge la connexion.

Afficher la configuration Rails depuis le conteneur :

```bash
docker compose exec rails bin/rails about
```

Tester la base :

```bash
docker compose exec rails bin/rails db:version
```

Préparer la base, si nécessaire :

```bash
docker compose exec rails bin/rails db:prepare
```

## 7. Créer le modèle et la migration

Rails génère le modèle, la migration et les tests associés avec une seule commande :

```bash
docker compose exec rails bin/rails generate model Livre \
  titre:string \
  auteur:string \
  annee_publication:integer \
  resume:text
```

La migration créée dans `db/migrate/` doit ressembler à ceci :

```ruby
class CreateLivres < ActiveRecord::Migration[7.1]
  def change
    create_table :livres do |t|
      t.string :titre, null: false
      t.string :auteur, null: false
      t.integer :annee_publication, null: false
      t.text :resume

      t.timestamps
    end
  end
end
```

Le modèle `app/models/livre.rb` :

```ruby
class Livre < ApplicationRecord
  validates :titre, presence: true
  validates :auteur, presence: true
  validates :annee_publication, presence: true,
                                  numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
```

Exécuter la migration dans Docker :

```bash
docker compose exec rails bin/rails db:migrate
```

Vérifier son état :

```bash
docker compose exec rails bin/rails db:migrate:status
```

## 8. Créer le contrôleur

```bash
docker compose exec rails bin/rails generate controller Livres index new
```

Dans `app/controllers/livres_controller.rb` :

```ruby
class LivresController < ApplicationController
  def index
    @livres = Livre.order(created_at: :desc)
  end

  def new
    @livre = Livre.new
  end

  def create
    @livre = Livre.new(livre_params)

    if @livre.save
      redirect_to livres_path, notice: "Livre ajouté avec succès."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def livre_params
    params.require(:livre).permit(
      :titre,
      :auteur,
      :annee_publication,
      :resume
    )
  end
end
```

Équivalence avec Laravel :

- `Livre.order(...)` correspond à une requête Eloquent `Livre::latest()->get()` ;
- `livre_params` correspond à la validation et aux champs autorisés ;
- `redirect_to livres_path` correspond à `redirect()->route('livres.index')` ;
- `render :new` réaffiche le formulaire avec les erreurs.

## 9. Déclarer les routes

Dans `config/routes.rb` :

```ruby
Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "livres#index"

  resources :livres, only: [:index, :new, :create]
end
```

Afficher les routes depuis Docker :

```bash
docker compose exec rails bin/rails routes
```

Les routes importantes sont :

| Méthode | URL interne Rails | URL publique |
|---|---|---|
| GET | `/` | `/rails/` |
| GET | `/livres` | `/rails/livres` |
| GET | `/livres/new` | `/rails/livres/new` |
| POST | `/livres` | `/rails/livres` |

## 10. Créer la vue de liste

Créer le dossier si nécessaire :

```bash
mkdir -p rails-app/src/app/views/livres
```

Créer `app/views/livres/index.html.erb` :

```erb
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <title>Livres - Rails</title>
</head>
<body>
  <h1>Livres <span>Rails</span></h1>

  <% if notice %>
    <p><%= notice %></p>
  <% end %>

  <p><%= link_to "Ajouter un livre", new_livre_path %></p>

  <table>
    <thead>
      <tr>
        <th>Titre</th>
        <th>Auteur</th>
        <th>Année</th>
      </tr>
    </thead>
    <tbody>
      <% if @livres.any? %>
        <% @livres.each do |livre| %>
          <tr>
            <td><%= livre.titre %></td>
            <td><%= livre.auteur %></td>
            <td><%= livre.annee_publication %></td>
          </tr>
        <% end %>
      <% else %>
        <tr>
          <td colspan="3">Aucun livre pour le moment.</td>
        </tr>
      <% end %>
    </tbody>
  </table>
</body>
</html>
```

## 11. Créer la vue du formulaire

Créer `app/views/livres/new.html.erb` :

```erb
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <title>Ajouter un livre - Rails</title>
</head>
<body>
  <h1>Ajouter un livre</h1>

  <p><%= link_to "Retour à la liste", livres_path %></p>

  <%= form_with model: @livre do |form| %>
    <% if @livre.errors.any? %>
      <div>
        <h2><%= pluralize(@livre.errors.count, "erreur") %> empêchent l'enregistrement :</h2>
        <ul>
          <% @livre.errors.full_messages.each do |message| %>
            <li><%= message %></li>
          <% end %>
        </ul>
      </div>
    <% end %>

    <div>
      <%= form.label :titre, "Titre" %>
      <%= form.text_field :titre %>
    </div>

    <div>
      <%= form.label :auteur, "Auteur" %>
      <%= form.text_field :auteur %>
    </div>

    <div>
      <%= form.label :annee_publication, "Année de publication" %>
      <%= form.number_field :annee_publication %>
    </div>

    <div>
      <%= form.label :resume, "Résumé" %>
      <%= form.text_area :resume, rows: 4 %>
    </div>

    <%= form.submit "Enregistrer" %>
  <% end %>
</body>
</html>
```

## 12. Conserver le préfixe `/rails` dans les URLs

Nginx retire le préfixe avant de transmettre la requête. Rails doit donc le remettre dans les helpers comme `livres_path` et `new_livre_path`.

Créer `config/initializers/forwarded_prefix.rb` :

```ruby
class ForwardedPrefix
  def initialize(app)
    @app = app
  end

  def call(env)
    prefix = env.fetch("HTTP_X_FORWARDED_PREFIX", "").to_s.chomp("/")
    env["SCRIPT_NAME"] = prefix unless prefix.empty?

    @app.call(env)
  end
end

Rails.application.config.middleware.insert_before 0, ForwardedPrefix
```

Cette solution ne contient pas de domaine en dur : avec `localhost`, une IP ou un nom de domaine, Rails reprend l'hôte reçu dans la requête et ajoute `/rails` comme préfixe.

Redémarrer Rails et Nginx après la modification :

```bash
docker compose restart rails nginx
```

## 13. Tester l'application

Tester les réponses HTTP :

```bash
curl -I http://localhost/rails/
curl -I http://localhost/rails/livres/new
```

Vérifier une URL générée :

```bash
curl -sS http://localhost/rails/ | grep -o 'livres/new'
```

Tester avec une adresse IP simulée :

```bash
curl -sS -H 'Host: 192.0.2.10' http://localhost/rails/ \
  | grep -o 'http://192.0.2.10/rails/livres/new'
```

Ouvrir ensuite dans un navigateur :

```text
http://localhost/rails/
```

Le bouton « Ajouter un livre » doit mener à :

```text
http://localhost/rails/livres/new
```

## 14. Commandes Docker utiles

```bash
# Voir les services
docker compose ps

# Voir les logs Rails
docker compose logs -f rails

# Ouvrir un shell dans le conteneur Rails
docker compose exec rails bash

# Exécuter une commande Rails
docker compose exec rails bin/rails <commande>

# Vider les caches temporaires
docker compose exec rails bin/rails tmp:clear

# Recréer la base en développement
# Attention : supprime les données.
docker compose exec rails bin/rails db:drop db:create db:migrate

# Arrêter les conteneurs
docker compose down

# Arrêter les conteneurs et supprimer les données PostgreSQL
# Attention : les livres seront supprimés.
docker compose down -v
```

## 15. Résultat attendu

L'application Rails permet de :

1. consulter la liste sur `/rails/` ou `/rails/livres` ;
2. ouvrir le formulaire sur `/rails/livres/new` ;
3. enregistrer un livre avec `POST /rails/livres` ;
4. revenir à la liste après l'enregistrement.

Les étapes et le résultat fonctionnel sont les mêmes qu'avec Laravel ; seuls les outils et conventions changent.

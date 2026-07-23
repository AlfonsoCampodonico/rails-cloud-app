# rails-cloud-app

A deliberately small **Rails 8** app, containerized and ready to ship. Its deploy
artifact is a Docker image (the stock Rails 8 `Dockerfile`), so it can run on any
container-capable host.

## What's inside

- **Rails 8.1** on **Ruby 3.3** (see `.ruby-version`)
- **SQLite** database (no external DB service required)
- Solid Queue / Solid Cache / Solid Cable (Rails 8 defaults)
- A welcome page at `/` (`WelcomeController`)
- A `Notes` scaffold (`/notes`) — a real DB-backed resource
- A health check at `/up` (returns 200 when the app boots cleanly)
- Stock production `Dockerfile` + **Kamal** deploy config (`config/deploy.yml`)

## Running locally

The host machine here has an old system Ruby (2.6), so everything is driven
through Docker on a `ruby:3.3` image — nothing is installed on your machine.

```bash
# From the project root:
docker run --rm -it -p 3000:3000 -v "$PWD":/work -w /work ruby:3.3 \
  bash -c "bundle install && bin/rails db:prepare && bin/rails server -b 0.0.0.0"
```

Then open http://localhost:3000.

If you install Ruby 3.3+ natively (e.g. `rbenv install 3.3.12`), the usual flow works too:

```bash
bundle install
bin/rails db:prepare
bin/rails server
```

## Building the deploy artifact (Docker image)

The image is what you ship. Rails needs `RAILS_MASTER_KEY` at runtime to decrypt
credentials — it's in `config/master.key` locally (git-ignored).

```bash
docker build -t rails-cloud-app .

docker run --rm -p 8080:80 \
  -e RAILS_MASTER_KEY="$(cat config/master.key)" \
  rails-cloud-app
# App is served on port 80 inside the container (Thruster) -> localhost:8080
```

## Deploying

The container image is the unit of deployment — point your target platform at
this repo/`Dockerfile`, and supply `RAILS_MASTER_KEY` as a secret.

- **Kamal** (Rails 8 default): edit `config/deploy.yml` (set your server IP,
  image/registry, and the `RAILS_MASTER_KEY` secret in `.kamal/secrets`), then
  `bin/kamal setup` / `bin/kamal deploy`.
- **Any container host**: build & push the image, run it with `RAILS_MASTER_KEY`
  set and port 80 exposed.

## Notes on the tests you may run

`POST /notes` without a CSRF token returns **422 `InvalidAuthenticityToken`** —
that's forgery protection working as designed, not an error. The in-browser form
includes the token automatically.

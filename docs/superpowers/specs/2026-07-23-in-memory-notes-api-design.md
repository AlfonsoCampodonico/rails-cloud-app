# In-memory Notes API + Rails-served fetch frontend

**Date:** 2026-07-23
**Status:** Approved

## Summary

Replace the SQLite-backed, Hotwire/Turbo-rendered Notes scaffold with:

- **No database at all** — notes live in-memory in the running Rails process (reset on restart/redeploy).
- **A JSON API** for note CRUD (`/notes`).
- **A single Rails-served HTML page** whose vanilla JavaScript talks to that API via `fetch()`.

Rails plays both roles: it serves the frontend page *and* answers the API calls. No Hotwire/Turbo, no separate static server, no JS build step.

## Goals

- Remove SQLite and, in fact, all database usage so the app boots with zero DB.
- Provide a "normal" JSON REST API for notes.
- Provide a "normal" client-side frontend (vanilla JS + `fetch`) served by Rails.

## Non-goals

- Persistence across restarts (in-memory is intentional).
- Authentication / multi-user isolation.
- Concurrency-safe storage at scale.
- Any front-end framework or build tooling.

## Architecture

### 1. Storage — `Note` as a PORO (`app/models/note.rb`)

`Note` no longer inherits from `ApplicationRecord`. It is a plain Ruby class:

- Instance attributes: `id`, `title`, `body`, `created_at`.
- Class-level store: `@notes = []` and an auto-increment `@next_id`.
- Class methods:
  - `all` → array of notes (newest-first ordering acceptable).
  - `find(id)` → note or `nil`.
  - `create(attrs)` → validates presence of `title`, assigns id + timestamp, appends, returns the note (and a way to signal validation failure).
  - `update(id, attrs)` → mutates and returns the note, or `nil` if not found.
  - `destroy(id)` → removes, returns boolean.
- Serialization: `as_json` / `to_h` returning `{ id, title, body, created_at }`.

Data lives only in process memory. This is the single source of truth; no migrations, no schema.

### 2. Backend — two controller roles

- **`WelcomeController#index`** (root `/`): renders the single HTML frontend page (ERB shell). Already the root route.
- **`NotesController`**: JSON-only. Actions `index`, `show`, `create`, `update`, `destroy`, each `render json:` with appropriate status codes:
  - `index` → `200` array of notes.
  - `show` → `200` note, or `404` if not found.
  - `create` → `201` note, or `422` with errors if invalid.
  - `update` → `200` note, or `404` / `422`.
  - `destroy` → `204` no content, or `404`.
  - Removes all HTML `respond_to` branches, jbuilder views, and the `set_note`/`ApplicationRecord` assumptions.

### 3. Frontend — one page, vanilla JS fetch

The root view (`app/views/welcome/index.html.erb`) contains:

- A note-creation form (title + body).
- A list container for existing notes, each with a delete control.
- An inline `<script type="module">` (or an importmap-pinned JS file) implementing:
  - `loadNotes()` → `GET /notes`, render list into DOM.
  - `createNote(title, body)` → `POST /notes`, then refresh list.
  - `deleteNote(id)` → `DELETE /notes/:id`, then refresh list.
- Reads the CSRF token from `<meta name="csrf-token">` and sends it as the `X-CSRF-Token` header on POST/PATCH/DELETE (Rails default forgery protection stays on).

### 4. Removing the database

- Delete `app/views/notes/*` (all ERB partials + jbuilder templates).
- Delete `db/migrate/*_create_notes.rb`, and the notes table from `db/schema.rb` (schema becomes empty / removed).
- Remove the `sqlite3` gem from the `Gemfile`.
- Rails 8 defaults wire cache / queue / cable to SQLite via `config/environments/production.rb` and `config/database.yml`. For a DB-free app:
  - Set cache store to `:memory_store`.
  - Set Active Job queue adapter to `:async` (in-process).
  - Set Action Cable adapter to `async` (`config/cable.yml`).
  - Remove `config/database.yml` and any `ActiveRecord`/database railtie usage so no DB connection is attempted at boot. (If fully unloading Active Record proves invasive, the fallback is to keep the railtie loaded but establish no connection; primary goal is the app boots with no database file.)

### 5. Data flow

```
Browser (fetch)  ──GET /notes──▶  NotesController#index  ──▶  Note.all  ──▶  JSON
Browser (form)   ──POST /notes─▶  NotesController#create ──▶  Note.create ─▶  201 JSON
Browser (delete) ──DELETE /notes/:id▶ NotesController#destroy ▶ Note.destroy ▶ 204
Browser (load)   ──GET /────────▶  WelcomeController#index ──▶  HTML shell page
```

## Error handling

- Not found (`find`/`update`/`destroy` on missing id) → `404 { error: "Not found" }`.
- Invalid create/update (blank title) → `422 { errors: { title: ["can't be blank"] } }`.
- Frontend surfaces API errors inline (simple message near the form); failed fetches do not silently no-op.

## Testing

- Request/integration spec covering the JSON API round-trip: create a note → appears in `index` → fetch via `show` → delete → gone (`404`).
- Assert status codes and JSON body shape.
- A smoke check that `GET /` returns `200` and serves the HTML shell.

## Open considerations / caveats

- In-memory store is process-local: multiple Puma workers would not share notes. For the demo, run a single worker or accept per-worker stores.
- Fully removing Active Record from a Rails 8 app can touch several config files; the fallback (keep AR loaded, no connection) is acceptable if cleaner.

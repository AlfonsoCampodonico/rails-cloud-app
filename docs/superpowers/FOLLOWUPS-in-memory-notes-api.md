# Known follow-ups — in-memory Notes API branch

Recorded at merge time (user chose to finish as-is; all findings deferred).
The in-memory demo runs and the full test suite passes (10 runs, 32 assertions, 0 failures). Active Record is fully unloaded.

## Deploy-blocking (out of scope per the plan; fix before any deploy)

- **`config/puma.rb:38`** — `plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]` remains, but `solid_queue` is no longer bundled. Setting `SOLID_QUEUE_IN_PUMA` crashes Puma at boot with `LoadError`. Delete the line.
- **`bin/jobs`** — `require "solid_queue/cli"` will `LoadError` if invoked. Remove/replace.
- **`bin/docker-entrypoint:5` and `bin/setup:24`** — call `bin/rails db:prepare`; the `db:*` rake namespace no longer exists without Active Record, so the container will not start and local setup fails. Remove/guard these calls.
- **`config/deploy.yml` / `Dockerfile`** — still reference a SQLite storage volume. Update for the DB-free app before deploying.

## Spec deviation (design spec promised "failed fetches do not silently no-op")

- **`app/views/welcome/index.html.erb`** — `add()` only handles HTTP 422; a 500 or network failure leaves `#error` empty and rejects unhandled. `remove()` ignores its response entirely. Add a `catch`/`!res.ok` branch that writes a generic message to `#error`.

## In-app polish / correctness

- **`app/models/note.rb`** — `Note.all` uses `sort_by(&:created_at).reverse`; Ruby's sort is not stable and two notes in the same `Time.now` tick can invert. Sort by `id` (monotonic) for deterministic newest-first ordering.
- **`app/models/note.rb`** — class-level `@notes`/`@next_id` mutations are not thread-safe (Puma default 3 threads) and state is per-worker. Acceptable per spec non-goals; add a one-line comment documenting the intentional non-persistent, non-thread-safe, single-worker design.
- **`app/controllers/notes_controller.rb`** — `update`'s `:invalid` branch hardcodes `{ title: ["can't be blank"] }` instead of reusing the model's `errors_hash`; risk of drift. Share a constant or build a throwaway `Note`.

## Test coverage gaps

- **`test/integration/notes_api_test.rb`** — asserts create-422, show-404, CRUD happy path. Add request-layer assertions for update-404, update-422, and destroy-404 to fully pin the controller's status-code contract (currently covered only at the model layer).
- **`test/models/note_test.rb`** — no direct test for `Note#errors_hash`; no string-id coercion test (`find/update/destroy "1"`).

## Dead cruft (harmless — none load at boot — but confusing)

- `config/recurring.yml` — `clear_solid_queue_finished_jobs` entry references a removed gem.
- `config/storage.yml`, `db/seeds.rb`, and the `# retry_on ActiveRecord::Deadlocked` comment in `app/jobs/application_job.rb` — orphaned references to removed infrastructure.
- `image_processing` gem remains in the Gemfile (Active Storage removed); harmless dead weight.

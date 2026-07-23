# Follow-ups — in-memory Notes API branch

Findings from the final whole-branch review. Initially deferred at merge, then
addressed in the follow-up commit "fix: address final-review follow-ups".
Status: ✅ done · ⬜ intentionally left.

The in-memory demo runs and the full test suite passes (15 runs, 44 assertions,
0 failures). Active Record is fully unloaded.

## Deploy-readiness

- ✅ `config/puma.rb` — removed the `plugin :solid_queue` line (gem is gone).
- ✅ `bin/jobs` — deleted (required `solid_queue/cli`).
- ✅ `bin/docker-entrypoint` / `bin/setup` — dropped the `bin/rails db:prepare` calls (no DB).
- ✅ `config/deploy.yml` — removed `SOLID_QUEUE_IN_PUMA` and the SQLite/Active Storage storage volume + `dbc` alias.
- ✅ `Dockerfile` — dropped the `sqlite3` and `libvips` apt packages.

## Spec fidelity

- ✅ `app/views/welcome/index.html.erb` — `add()`, `remove()`, and `load()` now
  surface non-422 and network failures in `#error` instead of silently no-op'ing,
  honoring the design spec ("failed fetches do not silently no-op").

## Correctness / quality

- ✅ `app/models/note.rb` — `Note.all` sorts by monotonic `id` (deterministic newest-first).
- ✅ Thread-safety / non-persistence documented in a comment on `Note`.
- ✅ Duplicated `"can't be blank"` string replaced by shared `Note::BLANK_TITLE_ERRORS`.

## Test coverage

- ✅ `test/integration/notes_api_test.rb` — added update-404, update-422, destroy-404.
- ✅ `test/models/note_test.rb` — added `errors_hash` and string-id coercion tests.

## Cleanup

- ✅ Removed orphaned `config/storage.yml`, `config/cache.yml`, `config/queue.yml`.
- ✅ Dropped the `image_processing` gem (Active Storage removed).
- ✅ Pruned dead `config/recurring.yml` and `app/jobs/application_job.rb` comments.
- ✅ Untracked `tmp/cache/*` (already covered by `.gitignore`).
- ⬜ `db/seeds.rb` — left as-is; it is standard Rails boilerplate comments only
  (references `db:seed`, which no longer exists, but nothing loads it).

# In-memory Notes API + Rails-served fetch frontend — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the SQLite-backed, Turbo-rendered Notes scaffold with a database-free app: notes held in memory, exposed via a JSON API, and driven by a Rails-served HTML page using `fetch()`.

**Architecture:** `Note` becomes a plain Ruby class with a class-level in-memory store. `NotesController` becomes JSON-only. The root page (`welcome#index`) serves an HTML shell whose vanilla JS calls the API. Active Record and all database-backed infrastructure (SQLite + solid_* adapters + Active Storage) are removed so the app boots with no database at all.

**Tech Stack:** Rails 8.1, Ruby, Puma, importmap (unused by our JS), Minitest.

## Global Constraints

- No database of any kind — the app must boot and pass tests with no database connection and no `config/database.yml`.
- No Hotwire/Turbo-driven CRUD — the frontend uses `fetch()` only. (Turbo gems may remain installed but must not drive note CRUD.)
- No JS build step — frontend JS is an inline `<script type="module">` in the view.
- In-memory store is intentionally non-persistent (resets on restart) and process-local.
- Keep Rails default CSRF protection ON; the frontend sends the `X-CSRF-Token` header on writes.
- Ruby style: 2-space indent, double-quoted strings (matches existing rubocop-omakase code).

---

## File Structure

- `app/models/note.rb` — **rewrite** as a PORO with in-memory class store (`all`, `find`, `create`, `update`, `destroy`, `reset!`, `valid?`, `errors_hash`, `as_json`).
- `app/controllers/notes_controller.rb` — **rewrite** as JSON-only CRUD.
- `app/views/welcome/index.html.erb` — **rewrite** as the frontend shell + inline fetch JS.
- `config/routes.rb` — **modify** to limit `notes` routes to API actions.
- `test/models/note_test.rb` — **create** unit tests for the store.
- `test/integration/notes_api_test.rb` — **create** API round-trip tests.
- Database removal (Task 4): `Gemfile`, `config/application.rb`, `config/environments/production.rb`, `config/cable.yml`, `test/test_helper.rb` — **modify**; `config/database.yml`, `db/schema.rb`, `db/migrate/20260723150238_create_notes.rb`, `db/cable_schema.rb`, `db/cache_schema.rb`, `db/queue_schema.rb`, `app/models/application_record.rb`, `app/views/notes/*` — **delete**.

---

### Task 1: `Note` in-memory PORO + unit tests

**Files:**
- Rewrite: `app/models/note.rb`
- Create: `test/models/note_test.rb`

**Interfaces:**
- Produces (class methods on `Note`):
  - `Note.all` → `Array<Note>` (newest first)
  - `Note.find(id)` → `Note` or `nil` (id coerced with `to_i`)
  - `Note.create(attrs)` → `Note` (always returns the built note; check `note.valid?`). `attrs` is a Hash with symbol keys `:title`, `:body`. Only stored if valid; assigns `id` (auto-increment from 1) and `created_at` (a `Time`).
  - `Note.update(id, attrs)` → `Note` on success, `nil` if id not found, `:invalid` if resulting title blank
  - `Note.destroy(id)` → `true`/`false`
  - `Note.reset!` → clears store and id counter (test helper)
  - Instance: `#id`, `#title`, `#body`, `#created_at` (accessors), `#valid?` → Boolean, `#errors_hash` → Hash, `#as_json(*)` → `{ id:, title:, body:, created_at: }`

**Note:** This task runs while Active Record is still loaded — that is fine; `Note` simply stops inheriting from it. AR is removed in Task 4.

- [ ] **Step 1: Write the failing tests**

Create `test/models/note_test.rb`:

```ruby
require "test_helper"

class NoteTest < ActiveSupport::TestCase
  setup { Note.reset! }

  test "create stores a valid note and assigns id and timestamp" do
    note = Note.create(title: "Hello", body: "World")
    assert note.valid?
    assert_equal 1, note.id
    assert_not_nil note.created_at
    assert_equal 1, Note.all.size
  end

  test "create with blank title is invalid and is not stored" do
    note = Note.create(title: "   ", body: "x")
    assert_not note.valid?
    assert_equal 0, Note.all.size
  end

  test "find returns the note by id and nil when missing" do
    note = Note.create(title: "A")
    assert_equal note.id, Note.find(note.id).id
    assert_nil Note.find(999)
  end

  test "update changes fields, returns nil for missing, :invalid for blank title" do
    note = Note.create(title: "A", body: "b")
    updated = Note.update(note.id, title: "B")
    assert_equal "B", updated.title
    assert_nil Note.update(999, title: "X")
    assert_equal :invalid, Note.update(note.id, title: "  ")
  end

  test "destroy removes the note and reports success" do
    note = Note.create(title: "A")
    assert Note.destroy(note.id)
    assert_equal 0, Note.all.size
    assert_not Note.destroy(999)
  end

  test "all returns notes newest first" do
    first = Note.create(title: "first")
    second = Note.create(title: "second")
    assert_equal [ second.id, first.id ], Note.all.map(&:id)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/note_test.rb`
Expected: FAIL (e.g. `NoMethodError: undefined method 'reset!'` or wrong behavior — the current `Note` is an empty ActiveRecord model).

- [ ] **Step 3: Rewrite `app/models/note.rb`**

```ruby
class Note
  @notes = []
  @next_id = 0

  class << self
    def all
      @notes.sort_by(&:created_at).reverse
    end

    def find(id)
      @notes.find { |note| note.id == id.to_i }
    end

    def create(attrs)
      note = new(attrs)
      return note unless note.valid?

      note.id = (@next_id += 1)
      note.created_at = Time.now
      @notes << note
      note
    end

    def update(id, attrs)
      note = find(id)
      return nil unless note

      new_title = attrs.fetch(:title, note.title)
      return :invalid if new_title.to_s.strip.empty?

      note.title = new_title
      note.body = attrs.fetch(:body, note.body)
      note
    end

    def destroy(id)
      note = find(id)
      return false unless note

      @notes.delete(note)
      true
    end

    def reset!
      @notes = []
      @next_id = 0
    end
  end

  attr_accessor :id, :title, :body, :created_at

  def initialize(attrs = {})
    @id = attrs[:id]
    @title = attrs[:title]
    @body = attrs[:body]
    @created_at = attrs[:created_at]
  end

  def valid?
    !title.to_s.strip.empty?
  end

  def errors_hash
    return {} if valid?

    { title: [ "can't be blank" ] }
  end

  def as_json(*)
    { id: id, title: title, body: body, created_at: created_at }
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/models/note_test.rb`
Expected: PASS (6 runs, 0 failures, 0 errors).

- [ ] **Step 5: Commit**

```bash
git add app/models/note.rb test/models/note_test.rb
git commit -m "feat: make Note an in-memory PORO store"
```

---

### Task 2: JSON-only `NotesController` + API integration tests

**Files:**
- Rewrite: `app/controllers/notes_controller.rb`
- Modify: `config/routes.rb`
- Create: `test/integration/notes_api_test.rb`

**Interfaces:**
- Consumes: `Note` class methods from Task 1.
- Produces HTTP endpoints:
  - `GET /notes` → `200` JSON array
  - `GET /notes/:id` → `200` JSON note, or `404 {"error":"Not found"}`
  - `POST /notes` (body `{"note":{"title","body"}}`) → `201` JSON note, or `422 {"errors":{"title":[...]}}`
  - `PATCH/PUT /notes/:id` → `200` JSON note, `404`, or `422`
  - `DELETE /notes/:id` → `204`, or `404`

- [ ] **Step 1: Write the failing tests**

Create `test/integration/notes_api_test.rb`:

```ruby
require "test_helper"

class NotesApiTest < ActionDispatch::IntegrationTest
  setup { Note.reset! }

  test "full CRUD round-trip over JSON" do
    post "/notes", params: { note: { title: "First", body: "Body" } }, as: :json
    assert_response :created
    created = JSON.parse(response.body)
    assert_equal "First", created["title"]
    id = created["id"]

    get "/notes", as: :json
    assert_response :success
    assert_equal 1, JSON.parse(response.body).size

    get "/notes/#{id}", as: :json
    assert_response :success
    assert_equal "First", JSON.parse(response.body)["title"]

    patch "/notes/#{id}", params: { note: { title: "Renamed" } }, as: :json
    assert_response :success
    assert_equal "Renamed", JSON.parse(response.body)["title"]

    delete "/notes/#{id}", as: :json
    assert_response :no_content

    get "/notes/#{id}", as: :json
    assert_response :not_found
  end

  test "create with blank title returns 422 with errors" do
    post "/notes", params: { note: { title: "" } }, as: :json
    assert_response :unprocessable_content
    assert_not_empty JSON.parse(response.body)["errors"]["title"]
  end

  test "show for a missing id returns 404" do
    get "/notes/999", as: :json
    assert_response :not_found
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/integration/notes_api_test.rb`
Expected: FAIL — the current controller renders ERB/HTML (missing templates) and routes still include HTML behaviors, so JSON assertions fail.

- [ ] **Step 3: Rewrite `app/controllers/notes_controller.rb`**

```ruby
class NotesController < ApplicationController
  def index
    render json: Note.all
  end

  def show
    note = Note.find(params[:id])
    return render_not_found unless note

    render json: note
  end

  def create
    note = Note.create(note_params)
    if note.valid?
      render json: note, status: :created
    else
      render json: { errors: note.errors_hash }, status: :unprocessable_content
    end
  end

  def update
    result = Note.update(params[:id], note_params)
    case result
    when nil
      render_not_found
    when :invalid
      render json: { errors: { title: [ "can't be blank" ] } }, status: :unprocessable_content
    else
      render json: result
    end
  end

  def destroy
    if Note.destroy(params[:id])
      head :no_content
    else
      render_not_found
    end
  end

  private
    def note_params
      params.require(:note).permit(:title, :body).to_h.symbolize_keys
    rescue ActionController::ParameterMissing
      {}
    end

    def render_not_found
      render json: { error: "Not found" }, status: :not_found
    end
end
```

- [ ] **Step 4: Limit routes in `config/routes.rb`**

Replace line 2 (`resources :notes`) with:

```ruby
  resources :notes, only: %i[ index show create update destroy ]
```

Leave the rest of the file unchanged (root, health check).

- [ ] **Step 5: Run tests to verify they pass**

Run: `bin/rails test test/integration/notes_api_test.rb`
Expected: PASS (3 runs, 0 failures, 0 errors).

- [ ] **Step 6: Commit**

```bash
git add app/controllers/notes_controller.rb config/routes.rb test/integration/notes_api_test.rb
git commit -m "feat: JSON-only Notes API backed by in-memory store"
```

---

### Task 3: Rails-served fetch frontend

**Files:**
- Rewrite: `app/views/welcome/index.html.erb`

**Interfaces:**
- Consumes: `GET/POST/DELETE /notes` from Task 2; reads CSRF token from `<meta name="csrf-token">` (already rendered by the layout via `csrf_meta_tags`).
- Produces: an HTML page at `/` with a create form (`#note-form` with `title` + `body` fields), a `#notes` list, and an `#error` message area, all driven by an inline module script.

**Note on `WelcomeController`:** the current `welcome#index` reads `@notes_count`. Check `app/controllers/welcome_controller.rb`; if it sets `@notes_count` (e.g. `Note.count`), remove that line so it does not call the now-removed AR method. The action should just render the view with no instance variables.

- [ ] **Step 1: Rewrite `app/views/welcome/index.html.erb`**

```erb
<div class="app">
  <h1>🚀 Notes</h1>
  <p class="lede">In-memory notes served by Rails, driven entirely by <code>fetch()</code>. Notes reset when the server restarts.</p>

  <form id="note-form" data-turbo="false" autocomplete="off">
    <input type="text" name="title" placeholder="Title" required>
    <textarea name="body" placeholder="Body (optional)" rows="2"></textarea>
    <button type="submit">Add note</button>
    <span id="error" class="error" role="alert"></span>
  </form>

  <ul id="notes" class="notes"></ul>
</div>

<script type="module">
  const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
  const list = document.getElementById("notes");
  const form = document.getElementById("note-form");
  const errorBox = document.getElementById("error");

  async function api(url, options = {}) {
    return fetch(url, {
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": csrfToken,
      },
      ...options,
    });
  }

  function render(notes) {
    list.replaceChildren();
    for (const note of notes) {
      const li = document.createElement("li");
      const title = document.createElement("strong");
      title.textContent = note.title;
      const body = document.createElement("p");
      body.textContent = note.body || "";
      const del = document.createElement("button");
      del.textContent = "Delete";
      del.addEventListener("click", () => remove(note.id));
      li.append(title, body, del);
      list.append(li);
    }
  }

  async function load() {
    const res = await api("/notes");
    render(await res.json());
  }

  async function add(title, body) {
    const res = await api("/notes", {
      method: "POST",
      body: JSON.stringify({ note: { title, body } }),
    });
    if (res.status === 422) {
      const data = await res.json();
      errorBox.textContent = "Title " + (data.errors?.title?.[0] || "is invalid");
      return false;
    }
    errorBox.textContent = "";
    return res.ok;
  }

  async function remove(id) {
    await api(`/notes/${id}`, { method: "DELETE" });
    load();
  }

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const title = form.title.value.trim();
    const body = form.body.value.trim();
    if (await add(title, body)) {
      form.reset();
      load();
    }
  });

  load();
</script>

<style>
  .app { max-width: 640px; margin: 3rem auto; padding: 0 1.5rem; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; color: #1f2937; }
  .app h1 { font-size: 2rem; margin-bottom: .25rem; }
  .lede { color: #6b7280; margin-bottom: 2rem; }
  #note-form { display: grid; gap: .5rem; margin-bottom: 2rem; }
  #note-form input, #note-form textarea { padding: .6rem; border: 1px solid #d1d5db; border-radius: 8px; font: inherit; }
  #note-form button { justify-self: start; padding: .5rem 1rem; border: 0; border-radius: 8px; background: #ef4444; color: #fff; font-size: .9rem; cursor: pointer; }
  .error { color: #b91c1c; font-size: .85rem; }
  .notes { list-style: none; padding: 0; display: grid; gap: .75rem; }
  .notes li { border: 1px solid #e5e7eb; border-radius: 12px; padding: 1rem; background: #fff; }
  .notes strong { display: block; margin-bottom: .25rem; }
  .notes p { margin: 0 0 .5rem; color: #4b5563; white-space: pre-wrap; }
  .notes button { border: 0; background: none; color: #ef4444; cursor: pointer; padding: 0; font-size: .85rem; }
</style>
```

- [ ] **Step 2: Clean up `WelcomeController` if needed**

Read `app/controllers/welcome_controller.rb`. If `index` assigns `@notes_count` (or any `Note`/AR call), reduce the action to an empty body:

```ruby
class WelcomeController < ApplicationController
  def index
  end
end
```

- [ ] **Step 3: Verify the page renders (manual + automated)**

Automated check is added in Task 2's suite conceptually; add a root smoke test to `test/integration/notes_api_test.rb`:

```ruby
  test "root serves the html frontend" do
    get "/"
    assert_response :success
    assert_match "id=\"note-form\"", response.body
  end
```

Run: `bin/rails test test/integration/notes_api_test.rb`
Expected: PASS (4 runs).

- [ ] **Step 4: Commit**

```bash
git add app/views/welcome/index.html.erb app/controllers/welcome_controller.rb test/integration/notes_api_test.rb
git commit -m "feat: fetch-driven Notes frontend served by Rails"
```

---

### Task 4: Remove the database entirely

**Files:**
- Modify: `Gemfile`, `config/application.rb`, `config/environments/production.rb`, `config/cable.yml`, `test/test_helper.rb`
- Delete: `config/database.yml`, `db/schema.rb`, `db/migrate/20260723150238_create_notes.rb`, `db/cable_schema.rb`, `db/cache_schema.rb`, `db/queue_schema.rb`, `app/models/application_record.rb`, and all files under `app/views/notes/`

**Interfaces:**
- Produces: an app that boots with no Active Record loaded and no database connection. `defined?(ActiveRecord)` is `nil` at runtime.

**Why the ordering matters:** `Bundler.require` loads the `solid_*` gems, which require Active Record. They must be removed from the `Gemfile` (Step 1) *before* Active Record is unloaded (Step 3), or boot fails.

- [ ] **Step 1: Remove database gems from `Gemfile`**

Delete these lines:

```ruby
# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 2.1"
```

```ruby
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"
```

```ruby
# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"
```

Then run: `bundle install`
Expected: bundle completes; `Gemfile.lock` no longer lists `sqlite3`, `solid_cache`, `solid_queue`, `solid_cable`, `jbuilder`.

- [ ] **Step 2: Delete database and scaffold files**

```bash
git rm config/database.yml db/schema.rb db/migrate/20260723150238_create_notes.rb \
       db/cable_schema.rb db/cache_schema.rb db/queue_schema.rb \
       app/models/application_record.rb
git rm -r app/views/notes
```

- [ ] **Step 3: Select Rails frameworks in `config/application.rb`**

Replace the top of the file (lines 1-7, through `Bundler.require`) with:

```ruby
require_relative "boot"

require "rails"
# Load only the frameworks this app uses — no Active Record (this app has no database),
# and therefore no Active Storage / Action Text / Action Mailbox (they depend on Active Record).
require "active_model/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)
```

Leave the `module RailsCloudApp` block unchanged.

- [ ] **Step 4: Swap database-backed adapters in `config/environments/production.rb`**

- Delete line: `config.active_storage.service = :local`
- Replace `config.cache_store = :solid_cache_store` with:
  ```ruby
  config.cache_store = :memory_store
  ```
- Replace the three solid_queue lines:
  ```ruby
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }
  ```
  with:
  ```ruby
  config.active_job.queue_adapter = :async
  ```
- Delete line: `config.active_record.dump_schema_after_migration = false`
- Delete line: `config.active_record.attributes_for_inspect = [ :id ]`

- [ ] **Step 5: Set Action Cable to async in `config/cable.yml`**

Replace the `production:` block with:

```yaml
production:
  adapter: async
```

- [ ] **Step 6: Remove `fixtures :all` from `test/test_helper.rb`**

Delete these two lines (the comment and the call):

```ruby
    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all
```

Leave `parallelize(...)` in place.

- [ ] **Step 7: Verify no database and full suite passes**

Run: `bin/rails runner "puts ActiveRecord rescue puts 'no active record'"`
Expected: prints `no active record` (Active Record is not loaded).

Run: `bin/rails test`
Expected: PASS — all model + integration tests green (10 runs total, 0 failures, 0 errors).

Run: `bin/rails runner "require 'net/http'; puts 'boot ok'"`
Expected: prints `boot ok` with no database-connection error.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "chore: remove Active Record, SQLite, and database-backed adapters"
```

---

## Out of scope (note for later)

- `config/deploy.yml` and the `Dockerfile` still reference a SQLite storage volume / `db:prepare`. Production deploy config is out of scope for this plan; the app runs and tests pass locally without touching it. Flag to the user if a deploy is attempted.
- Turbo/Stimulus gems remain installed but unused for CRUD (`data-turbo="false"` on the form prevents interception). Removing them entirely is optional cleanup, not required.

## Self-Review

- **Spec coverage:** Storage PORO (Task 1) ✓; JSON API (Task 2) ✓; fetch frontend + CSRF (Task 3) ✓; full DB removal incl. solid_* + Active Storage + database.yml (Task 4) ✓; error handling 404/422 (Tasks 1-2) ✓; tests round-trip + root smoke (Tasks 1-3) ✓.
- **Placeholder scan:** none — all steps contain concrete code/commands.
- **Type consistency:** `Note.update` returns `Note`/`nil`/`:invalid` consistently across model, tests, and controller; `note_params` produces symbol-keyed hashes matching `Note`'s `attrs[:title]`/`attrs[:body]` access; `as_json` keys (`id/title/body/created_at`) match frontend usage (`note.title`, `note.body`, `note.id`).

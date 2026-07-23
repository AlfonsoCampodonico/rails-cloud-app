# In-memory note store. Intentionally non-persistent (state lives only in the
# running process and resets on restart) and NOT thread-safe: the class-level
# @notes array and @next_id counter are mutated without locking. This is fine
# for the single-worker demo it was built for; it is not production storage.
class Note
  # Shared so the model and controller report an identical validation error.
  BLANK_TITLE_ERRORS = { title: [ "can't be blank" ] }.freeze

  @notes = []
  @next_id = 0

  class << self
    def all
      # Sort by id (strictly monotonic) rather than created_at so ordering is
      # deterministic even when two notes share a Time.now tick.
      @notes.sort_by(&:id).reverse
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

    BLANK_TITLE_ERRORS
  end

  def as_json(*)
    { id: id, title: title, body: body, created_at: created_at }
  end
end

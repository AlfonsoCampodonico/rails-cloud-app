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

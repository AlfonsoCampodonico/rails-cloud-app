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

  test "errors_hash is empty when valid and reports a blank title otherwise" do
    assert_empty Note.new(title: "Present").errors_hash
    assert_equal [ "can't be blank" ], Note.new(title: " ").errors_hash[:title]
  end

  test "find, update, and destroy coerce string ids" do
    note = Note.create(title: "A")
    assert_equal note.id, Note.find(note.id.to_s).id
    assert_equal "B", Note.update(note.id.to_s, title: "B").title
    assert Note.destroy(note.id.to_s)
    assert_equal 0, Note.all.size
  end
end

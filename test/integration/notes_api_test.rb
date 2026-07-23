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

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

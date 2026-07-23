class WelcomeController < ApplicationController
  def index
    @notes_count = Note.count
  end
end

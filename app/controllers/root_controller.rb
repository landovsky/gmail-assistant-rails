class RootController < ApplicationController
  def index
    redirect_to "/api/debug/emails", allow_other_host: false
  end
end

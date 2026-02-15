class RootController < ApplicationController
  def index
    redirect_to "/admin/emails", allow_other_host: false
  end
end

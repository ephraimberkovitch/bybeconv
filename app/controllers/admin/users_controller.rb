class Admin::UsersController < ApplicationController
  before_filter :admin_required

  def index
    render :text => 'Hello from the admin panel!'
  end
end

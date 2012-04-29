class User < ActiveRecord::Base
  has_many :auth_services
  
  attr_accessible :name, :email, :admin
end

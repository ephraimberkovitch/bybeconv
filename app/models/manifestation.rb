class Manifestation < ActiveRecord::Base
  has_and_belongs_to_many :expressions
end
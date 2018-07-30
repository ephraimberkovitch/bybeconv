class Holding < ActiveRecord::Base
  attr_accessible :location
  belongs_to :publication
  belongs_to :bib_source
  enum status: [:todo, :scanned, :obtained, :missing]
end

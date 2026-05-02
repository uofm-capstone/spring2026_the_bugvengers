class SponsorSurvey < ApplicationRecord
  belongs_to :team
  has_one_attached :csv

  validates :sprint_number, presence: true
  validates :sprint_number, numericality: { only_integer: true }
  validates :team_id, uniqueness: { scope: :sprint_number }
end

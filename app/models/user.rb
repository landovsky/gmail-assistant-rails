class User < ApplicationRecord
  has_many :user_labels, dependent: :destroy
  has_many :user_settings, dependent: :destroy
  has_one :sync_state, dependent: :destroy
  has_many :emails, dependent: :destroy
  has_many :email_events, dependent: :destroy
  has_many :jobs, dependent: :destroy
  has_many :llm_calls, dependent: :destroy
  has_many :agent_runs, dependent: :destroy

  validates :email, presence: true, uniqueness: true

  scope :active, -> { where(is_active: true) }
  scope :onboarded, -> { where.not(onboarded_at: nil) }
end

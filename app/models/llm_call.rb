class LlmCall < ApplicationRecord
  belongs_to :user, optional: true

  CALL_TYPES = %w[classify draft rework context agent].freeze

  validates :call_type, presence: true, inclusion: { in: CALL_TYPES }
  validates :model, presence: true
end

class LlmCall < ApplicationRecord
  # Associations
  belongs_to :user, optional: true

  # Validations
  validates :call_type, presence: true, inclusion: {
    in: %w[classify draft rework context agent],
    message: "%{value} is not a valid call type"
  }
  validates :model, presence: true
end

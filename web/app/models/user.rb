class User < ApplicationRecord
  ROLES = %w[viewer analyst admin].freeze
  ROLE_PRIORITY = ROLES.each_with_index.to_h.freeze

  has_secure_password

  normalizes :email, with: ->(value) { value.to_s.strip.downcase }

  validates :email,
    presence: true,
    format: { with: URI::MailTo::EMAIL_REGEXP },
    uniqueness: { case_sensitive: false }
  validates :role, presence: true, inclusion: { in: ROLES }

  def at_least_role?(required_role)
    required_rank = ROLE_PRIORITY[required_role.to_s]
    return false if required_rank.nil?

    ROLE_PRIORITY.fetch(role, -1) >= required_rank
  end
end

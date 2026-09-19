module Identity
  class User < ApplicationRecord
    MIN_PASSWORD_LENGTH = 12

    has_secure_password
    has_many :memberships, dependent: :restrict_with_exception
    has_many :organizations, through: :memberships
    has_many :sessions, dependent: :delete_all

    normalizes :email, with: ->(email) { email.strip.downcase }

    validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: { case_sensitive: false }
    validates :name, presence: true
    validates :password, length: { minimum: MIN_PASSWORD_LENGTH }, allow_nil: true

    def membership_in(organization)
      memberships.find_by(organization:)
    end
  end
end

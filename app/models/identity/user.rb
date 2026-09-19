module Identity
  class User < ApplicationRecord
    MIN_PASSWORD_LENGTH = 12

    # reset_token: gives password_reset_token, find_by_password_reset_token
    # and find_by_password_reset_token! for free, bound to the password
    # salt so a token stops working after one use or any password change
    # (ADR 0007's 20 minute expiry, the default is 15).
    has_secure_password reset_token: { expires_in: 20.minutes }
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

    # For structured logs about an email that never reaches the log itself
    # (ADR 0007: failed sign-ins are logged with a hashed email). Keyed with
    # the app secret, not a plain digest, so log access plus a candidate
    # list of addresses cannot dictionary-match its way back to the email.
    def self.email_digest(email)
      OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, email.to_s.strip.downcase)
    end
  end
end

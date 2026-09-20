module Identity
  # A pending membership offer, opened by its token by someone who belongs
  # to no organization yet (ADR 0003). Only the SHA-256 digest of the token
  # is stored, same as Identity::Session, so a copy of this table cannot be
  # used to accept.
  class Invitation < ApplicationRecord
    include TenantScoped

    EXPIRY = 7.days

    belongs_to :invited_by, class_name: "Identity::User", foreign_key: :invited_by_user_id, inverse_of: false
    belongs_to :accepted_by, class_name: "Identity::User", foreign_key: :accepted_by_user_id, optional: true, inverse_of: false

    normalizes :email, with: ->(email) { email.strip.downcase }

    validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :role, inclusion: { in: Identity::Membership::ROLES }
    validates :token_digest, presence: true

    # Still an open offer: what the members screen lists as cancellable.
    scope :pending, -> { where(accepted_at: nil).where("expires_at > ?", Time.current) }

    def self.digest(token) = OpenSSL::Digest::SHA256.hexdigest(token)

    # Reads the invitation's organization through the SECURITY DEFINER
    # lookup (ADR 0003), applies it as the RLS tenant, then loads the row
    # through the ordinary tenant-scoped query. Returns nil for an unknown,
    # expired or already accepted token, without distinguishing which
    # (api-contract skill: error messages do not reveal which).
    def self.find_by_token(token, now: Time.current)
      return if token.blank?

      digest_value = digest(token)
      connection = ActiveRecord::Base.lease_connection
      organization_id = connection.select_value(
        "SELECT invitation_organization_id(#{connection.quote(digest_value)})"
      )
      return unless organization_id

      # TenantScoped's default scope reads Current.organization (the Ruby
      # attribute), not the Postgres setting, so both must be set before the
      # find_by below, same as start_browser_session! does on the write side.
      Current.organization = Identity::Organization.find(organization_id)
      TenantSetting.apply!(organization_id)
      invitation = find_by(token_digest: digest_value)
      return if invitation.nil? || invitation.expired?(now) || invitation.accepted?

      invitation
    end

    def expired?(now = Time.current) = now >= expires_at
    def accepted? = accepted_at.present?
  end
end

module Identity
  # A signed-in browser. Only the SHA-256 digest of the token is stored, so a
  # copy of this table cannot be used to sign in (ADR 0007).
  class Session < ApplicationRecord
    IDLE_TIMEOUT = 30.minutes
    ABSOLUTE_TIMEOUT = 12.hours
    TOUCH_INTERVAL = 1.minute

    belongs_to :user
    belongs_to :organization

    def self.digest(token) = OpenSSL::Digest::SHA256.hexdigest(token)

    # Returns the session and the raw token, which only the cookie will hold.
    def self.start!(user:, organization:, ip:, user_agent:, now: Time.current)
      token = SecureRandom.urlsafe_base64(32)
      session = create!(
        user:, organization:,
        token_digest: digest(token),
        ip: (ip unless user.demo?),
        user_agent: (user_agent unless user.demo?),
        created_at: now,
        updated_at: now,
        last_seen_at: now
      )
      [ session, token ]
    end

    # Finds the live session for a token, deleting it when it has expired.
    def self.resume(token, now: Time.current)
      return if token.blank?

      session = find_by(token_digest: digest(token))
      return unless session
      return session.tap { it.touch_if_stale(now) } unless session.expired?(now)

      session.destroy!
      nil
    end

    def expired?(now = Time.current)
      last_seen_at <= now - IDLE_TIMEOUT || created_at <= now - ABSOLUTE_TIMEOUT
    end

    def touch_if_stale(now = Time.current)
      update_column(:last_seen_at, now) if last_seen_at <= now - TOUCH_INTERVAL
    end
  end
end

module Audit
  # Append-only (ADR 0010): the database rejects UPDATE and DELETE from
  # every role but the owner, so nothing here provides them either.
  class Event < ApplicationRecord
    include TenantScoped

    self.table_name = "audit_events"

    belongs_to :actor, class_name: "Identity::User", foreign_key: :actor_user_id, inverse_of: false

    validates :action, presence: true
    validates :subject_type, presence: true
    validates :subject_id, presence: true
  end
end

# ADR 0005. One row per critical write attempt that succeeded: it is inserted
# first inside the command transaction and committed with the effect, so a
# failed attempt leaves nothing behind and can be retried with the same key.
class IdempotencyKey < ApplicationRecord
  include TenantScoped

  belongs_to :user, class_name: "Identity::User"
end

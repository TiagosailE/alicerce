# Shared by simple update commands that record a plain before/after diff on
# save (ADR 0010). Not for personal-data fields: a caller with any (e.g.
# Catalog::Partner) must redact those itself before calling Audit.record.
module AuditsUpdates
  extend ActiveSupport::Concern

  private
    def field_changes(record, exclude: %w[created_at updated_at revision])
      record.saved_changes.except(*exclude).transform_values { |(from, to)| { from:, to: } }
    end
end

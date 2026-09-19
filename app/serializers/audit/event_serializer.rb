module Audit
  class EventSerializer
    def initialize(event)
      @event = event
    end

    def as_json
      {
        id: @event.id,
        action: @event.action,
        subject_type: @event.subject_type,
        subject_id: @event.subject_id,
        field_changes: @event.field_changes,
        actor: Identity::UserSerializer.new(@event.actor).as_json,
        created_at: @event.created_at.iso8601
      }
    end
  end
end

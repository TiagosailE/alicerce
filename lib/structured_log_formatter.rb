require "json"

# One JSON object per log line (docs/security.md's Observability target),
# tagged with the request, user and organization when known. Current
# (ADR 0010) is already populated by the time application code logs
# anything, so this reads it directly instead of the log_tags/
# TaggedLogging machinery, which only ever prepends bracketed text to the
# message and cannot turn tags into real JSON fields.
#
# A Hash message (Rails.logger.warn(event: "...", ...)) is merged as
# top-level fields, for a deliberate structured event; any other message is
# put under "message", the ordinary case (framework and gem log lines).
class StructuredLogFormatter < ::Logger::Formatter
  def call(severity, time, _progname, msg)
    payload = {
      severity: severity,
      time: time.utc.iso8601(3),
      request_id: Current.request_id,
      user_id: Current.user&.id,
      organization_id: Current.organization&.id
    }
    payload.merge!(msg.is_a?(Hash) ? msg : { message: msg2str(msg) })
    "#{payload.compact.to_json}\n"
  end
end

# Audit.record(action, subject, actor:, changes:) is how a command writes
# to the append-only trail (ADR 0010), in its own transaction so the event
# commits or rolls back with the change it describes. request_id and
# ip_prefix come from Current, set once per request in
# Api::V1::BaseController, so callers never thread them through by hand.
#
# changes holds the fields the caller wants recorded. Personal data (names
# of people, CPF, email, phone, address) and free-text fields must arrive
# already redacted to "changed" without a value: this method stores
# whatever it is given, it does not know which fields are personal per
# domain.
module Audit
  module_function

  def record(action, subject, actor:, changes: {})
    Event.create!(
      organization: Current.organization,
      actor_user_id: actor.id,
      action: action.to_s,
      subject_type: subject.class.name,
      subject_id: subject.id,
      field_changes: changes,
      request_id: Current.request_id,
      ip_prefix: Current.ip_prefix
    )
  end

  # The /24 of an IPv4 address or the /48 of an IPv6 one (ADR 0010): never
  # store the full address.
  def ip_prefix(remote_ip)
    return nil if remote_ip.blank?

    address = IPAddr.new(remote_ip)
    prefix_length = address.ipv4? ? 24 : 48
    "#{address.mask(prefix_length)}/#{prefix_length}"
  rescue IPAddr::Error
    nil
  end
end

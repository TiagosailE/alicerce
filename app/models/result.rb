# What a command returns (backend-conventions skill): success carries the
# domain object, failure carries a symbol from that command's own closed
# list of error codes plus any details the controller forwards to the
# client. Never raised; commands raise only for bugs and infrastructure
# errors.
Result = Data.define(:value, :error, :details) do
  def self.success(value = nil) = new(value:, error: nil, details: {})
  def self.failure(error, details = {}) = new(value: nil, error:, details:)

  # A :validation_failed failure built from a model's own errors, in the
  # same details.fields shape the API contract uses everywhere else.
  def self.invalid(record)
    fields = record.errors.group_by { |error| error.attribute.to_s }
      .transform_values { |errors| errors.map { |error| error.type.to_s } }
    failure(:validation_failed, fields:)
  end

  def success? = error.nil?
end

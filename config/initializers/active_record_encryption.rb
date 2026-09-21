# Catalog::Partner#document_number needs deterministic encryption at rest
# (ADR 0012). config/credentials is not used in this project, so the three
# keys Active Record Encryption needs come from the environment, the same
# way SECRET_KEY_BASE and BREVO_API_KEY already do. Development and test
# get fixed, non-secret values so a fresh clone works with no extra setup,
# the same exemption Rails itself already gives SECRET_KEY_BASE outside
# production.
if Rails.env.local?
  Rails.application.config.active_record.encryption.primary_key = "alicerce-development-primary-key"
  Rails.application.config.active_record.encryption.deterministic_key = "alicerce-development-deterministic-key"
  Rails.application.config.active_record.encryption.key_derivation_salt = "alicerce-development-key-derivation-salt"
else
  Rails.application.config.active_record.encryption.primary_key = ENV.fetch("AR_ENCRYPTION_PRIMARY_KEY")
  Rails.application.config.active_record.encryption.deterministic_key = ENV.fetch("AR_ENCRYPTION_DETERMINISTIC_KEY")
  Rails.application.config.active_record.encryption.key_derivation_salt = ENV.fetch("AR_ENCRYPTION_KEY_DERIVATION_SALT")
end

require "spec_helper"

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

Rails.root.glob("spec/support/**/*.rb").sort.each { |file| require file }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# The schema is loaded as the owner; the examples run as the application role,
# with production grants and under row level security (ADR 0003).
ActiveRecord::Base.with_connection { |connection| DatabaseRoles.prepare!(connection) }
# Kept for the few examples that must act as the owner (spec/support/owner_connection.rb).
OWNER_DB_CONFIG = ActiveRecord::Base.connection_db_config.configuration_hash.dup.freeze
ActiveRecord::Base.establish_connection(
  DatabaseRoles.app_connection_config(ActiveRecord::Base.connection_db_config.configuration_hash)
)

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.include FactoryBot::Syntax::Methods
end

require "rails_helper"

RSpec.describe "Unsafe migrations" do
  it "are refused before they reach a database that is serving traffic" do
    migration = Class.new(ActiveRecord::Migration[8.1]) do
      def change
        remove_column :solid_queue_jobs, :priority
      end
    end

    expect { migration.new.migrate(:up) }.to raise_error(StrongMigrations::UnsafeMigration)
  end
end

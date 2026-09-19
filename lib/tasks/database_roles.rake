namespace :db do
  desc "Create the application role and grant it row privileges (development and test)"
  task app_role: :environment do
    next if Rails.env.production?

    ActiveRecord::Base.with_connection { |connection| DatabaseRoles.prepare!(connection) }
  end
end

%w[db:prepare db:migrate db:schema:load db:reset].each do |task_name|
  Rake::Task[task_name].enhance { Rake::Task["db:app_role"].invoke } if Rake::Task.task_defined?(task_name)
end

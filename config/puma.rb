threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

port ENV.fetch("PORT", 3000)

plugin :tmp_restart if ENV.fetch("RAILS_ENV", "development") == "development"

# Jobs run as threads inside this process (async mode) instead of a forked
# supervisor with its own worker, dispatcher and scheduler processes.
if ENV["SOLID_QUEUE_IN_PUMA"]
  plugin :solid_queue
  solid_queue_mode :async
end

pidfile ENV["PIDFILE"] if ENV["PIDFILE"]

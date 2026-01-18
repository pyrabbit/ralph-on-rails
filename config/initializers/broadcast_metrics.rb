# Start broadcasting metrics when the server boots
Rails.application.config.after_initialize do
  # Only start in server mode (not console, rake tasks, etc)
  if defined?(Rails::Server)
    BroadcastMetricsJob.perform_later
  end
end

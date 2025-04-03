Rails.application.config.after_initialize do
  if Rails.env.production? || Rails.env.development?
    Rails.logger.info('Crash test initializer loaded. Application will crash in 30 seconds.')

    Thread.new do
      sleep 30
      Rails.logger.error('Intentionally crashing the application for Coolify restart test')
      # Force process to exit with status code 1
      Process.kill('KILL', Process.pid)
    end
  end
end

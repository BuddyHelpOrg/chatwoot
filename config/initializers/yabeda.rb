# Check if the current process is the Rails web server and not a Sidekiq worker
if defined?(Rails::Server) || ENV['PROCESS_TYPE'] == 'web'
  Yabeda::Rails.install!
end

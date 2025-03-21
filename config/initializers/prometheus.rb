require 'prometheus/client'
require 'prometheus_exporter/middleware' if defined?(PrometheusExporter)

if Rails.env.production? || Rails.env.development?
  begin
    # Create and get a default Prometheus registry
    prometheus_registry = Prometheus::Client.registry

    # Use Sidekiq Prometheus Exporter if Sidekiq is being used
    if defined?(Sidekiq) && defined?(Sidekiq::PrometheusExporter)
      Sidekiq::PrometheusExporter.configure do |config|
        config.registry = prometheus_registry
      end
    end

    # Add default metrics (process metrics like memory, CPU, etc.)
    # require 'prometheus/client/rack/collector' # Comment out since this isn't available
    
    # Create custom metrics
    CHATWOOT_REQUEST_DURATION = prometheus_registry.histogram(
      :chatwoot_request_duration_seconds,
      docstring: 'Duration of Chatwoot HTTP requests in seconds',
      labels: [:path, :method, :status],
      buckets: [0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
    )
    
    CHATWOOT_CONTROLLER_DURATION = prometheus_registry.histogram(
      :chatwoot_controller_duration_seconds,
      docstring: 'Duration of Chatwoot controller actions in seconds',
      labels: [:controller, :action, :status],
      buckets: [0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]
    )

    CHATWOOT_REQUEST_COUNT = prometheus_registry.counter(
      :chatwoot_request_count,
      docstring: 'Count of Chatwoot HTTP requests',
      labels: [:path, :method, :status]
    )

    CHATWOOT_DB_QUERY_DURATION = prometheus_registry.histogram(
      :chatwoot_db_query_duration_seconds,
      docstring: 'Duration of database queries in seconds',
      labels: [:query_type],
      buckets: [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5]
    )
    
    # Business metrics
    CHATWOOT_CONVERSATIONS_CREATED = prometheus_registry.counter(
      :chatwoot_conversations_created_total,
      docstring: 'Number of conversations created'
    )
    
    CHATWOOT_CONVERSATIONS_RESOLVED = prometheus_registry.counter(
      :chatwoot_conversations_resolved_total,
      docstring: 'Number of conversations resolved'
    )
    
    CHATWOOT_MESSAGES_CREATED = prometheus_registry.counter(
      :chatwoot_messages_created_total,
      docstring: 'Number of messages created',
      labels: [:message_type]
    )
    
    CHATWOOT_USERS_ACTIVE = prometheus_registry.gauge(
      :chatwoot_users_active,
      docstring: 'Number of active users'
    )
    
    # Set initial values for gauges based on database - defer this to after model loading
    # Will be initialized when the app starts
    begin
      Rails.application.config.after_initialize do
        if defined?(User) && defined?(Account)
          CHATWOOT_USERS_ACTIVE.set(User.where(account_id: Account.all.pluck(:id)).distinct.count) rescue 0
        end
      end
    rescue => e
      Rails.logger.error("Error initializing Prometheus user metrics: #{e.message}")
    end
    
    # Initialize the middleware
    if defined?(PrometheusExporter) && defined?(PrometheusExporter::Middleware)
      Rails.application.config.middleware.use PrometheusExporter::Middleware
    end
    
    # Instrument Rails
    ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, start, finish, _id, payload|
      if payload[:name] != 'SCHEMA'
        duration = finish - start
        CHATWOOT_DB_QUERY_DURATION.observe(duration, labels: { query_type: payload[:name] })
      end
    end
    
    # Instrument Controller Actions
    ActiveSupport::Notifications.subscribe('process_action.action_controller') do |_name, start, finish, _id, payload|
      labels = {
        path: payload[:path],
        method: payload[:method],
        status: payload[:status]
      }
      duration = finish - start
      CHATWOOT_REQUEST_DURATION.observe(duration, labels: labels)
      CHATWOOT_REQUEST_COUNT.increment(labels: labels)
    end
  rescue => e
    Rails.logger.error("Error initializing Prometheus: #{e.message}")
    # Continue booting the app even if Prometheus isn't available
  end
end
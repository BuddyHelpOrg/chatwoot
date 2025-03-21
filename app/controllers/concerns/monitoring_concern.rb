module MonitoringConcern
  extend ActiveSupport::Concern

  included do
    around_action :monitor_controller_action, if: -> { Rails.env.production? || Rails.env.development? }

    private

    def monitor_controller_action
      start_time = Time.now

      yield

      # Skip for non-API requests or assets
      return if request.path.starts_with?('/assets') || request.path.starts_with?('/packs')

      begin
        duration = Time.now - start_time
        labels = {
          controller: self.class.name,
          action: action_name,
          status: response.status
        }

        # Record custom metrics if Prometheus is available
        CHATWOOT_CONTROLLER_DURATION.observe(duration, labels: labels) if defined?(CHATWOOT_CONTROLLER_DURATION)
      rescue StandardError => e
        Rails.logger.error("Error in monitoring controller action: #{e.message}")
        # Continue with the request even if monitoring fails
      end
    end
  end
end

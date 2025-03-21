module PrometheusInstrumentable
  extend ActiveSupport::Concern

  included do
    after_create :increment_create_counter
    after_update :track_status_change, if: -> { defined?(status_changed?) && status_changed? }
  end

  private

  def increment_create_counter
    return unless defined?(Prometheus::Client) && Prometheus::Client.registry

    case self.class.name
    when 'Conversation'
      CHATWOOT_CONVERSATIONS_CREATED.increment if defined?(CHATWOOT_CONVERSATIONS_CREATED)
    when 'Message'
      CHATWOOT_MESSAGES_CREATED.increment(labels: { message_type: message_type }) if defined?(CHATWOOT_MESSAGES_CREATED)
    when 'User'
      recalculate_active_users if defined?(CHATWOOT_USERS_ACTIVE)
    end
  end

  def track_status_change
    return unless defined?(Prometheus::Client) && Prometheus::Client.registry

    case self.class.name
    when 'Conversation'
      CHATWOOT_CONVERSATIONS_RESOLVED.increment if status == 'resolved' && defined?(CHATWOOT_CONVERSATIONS_RESOLVED)
    end
  end

  def recalculate_active_users
    CHATWOOT_USERS_ACTIVE.set(User.where(account_id: Account.all.pluck(:id)).distinct.count)
  end
end

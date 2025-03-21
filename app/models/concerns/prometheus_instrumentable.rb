module PrometheusInstrumentable
  extend ActiveSupport::Concern

  included do
    after_create :increment_create_counter
    after_update :track_status_change, if: -> { defined?(status_changed?) && status_changed? }
  end

  private

  def increment_create_counter
    return unless defined?(Prometheus::Client)

    case self.class.name
    when 'Account', 'User', 'Inbox', 'Team'
      metric_name = "chatwoot_#{self.class.name.downcase}_created_total"
      METRICS_REGISTRY.get(metric_name)&.increment
    when 'Conversation'
      increment_conversation_create_counter
    when 'Message'
      increment_message_create_counter
    end
  end

  def increment_conversation_create_counter
    CHATWOOT_CONVERSATIONS_CREATED_TOTAL.increment(source: source.to_s, inbox_type: inbox.inbox_type)
  end

  def increment_message_create_counter
    CHATWOOT_MESSAGES_CREATED_TOTAL.increment(
      message_type: message_type.to_s,
      source: source_name
    )
  end

  def track_status_change
    return unless defined?(Prometheus::Client) && Prometheus::Client.registry

    case self.class.name
    when 'Conversation'
      CHATWOOT_CONVERSATIONS_RESOLVED.increment if status == 'resolved' && defined?(CHATWOOT_CONVERSATIONS_RESOLVED)
    end
  end

  def recalculate_active_users
    CHATWOOT_USERS_ACTIVE.set(User.where(account_id: Account.all.select(:id)).distinct.count)
  end
end

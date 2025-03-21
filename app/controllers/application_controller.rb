class ApplicationController < ActionController::Base
  include DeviseTokenAuth::Concerns::SetUserByToken
  include RequestExceptionHandler
  include Pundit::Authorization
  include SwitchLocale
  # Re-enable monitoring concern
  include MonitoringConcern if defined?(MonitoringConcern)

  skip_before_action :verify_authenticity_token

  before_action :set_current_user, unless: :devise_controller?
  around_action :switch_locale
  around_action :handle_with_exception, unless: :devise_controller?

  private

  def set_current_user
    @user ||= current_user
    Current.user = @user
  end

  def pundit_user
    {
      user: Current.user,
      account: Current.account,
      account_user: Current.account_user
    }
  end
end
# Only include enterprise modules if they exist
ApplicationController.include_mod_with('Concerns::ApplicationControllerConcern') if ChatwootApp.enterprise?

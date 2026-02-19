class ApplicationController < ActionController::Base
  LOCALHOST_HOSTS = %w[localhost 127.0.0.1 ::1].freeze

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Entity pages also use a few shared formatting helpers (ex: format_salary).
  helper SalaryBookHelper

  # Canonical slug-first URLs w/ numeric fallbacks.
  helper EntityLinksHelper

  before_action :set_current_user
  before_action :require_authentication!

  helper_method :current_user, :user_signed_in?, :auth_bypassed_for_localhost?

  class << self
    def require_role(role, **options)
      before_action(**options) { enforce_role!(role) }
    end
  end

  private

  def set_current_user
    Current.user = nil
    return if auth_bypassed_for_localhost?
    return if session[:user_id].blank?

    Current.user = User.find_by(id: session[:user_id])
  end

  def current_user
    Current.user
  end

  def user_signed_in?
    current_user.present?
  end

  def require_authentication!
    return if auth_bypassed_for_localhost?
    return if user_signed_in?

    store_return_location!
    deny_unauthenticated_access!
  end

  def enforce_role!(required_role)
    return if auth_bypassed_for_localhost?
    return if current_user&.at_least_role?(required_role)

    deny_forbidden_access!
  end

  def deny_unauthenticated_access!
    respond_to do |format|
      format.html do
        redirect_to login_path, alert: "Please sign in to continue."
      end
      format.json { render json: { error: "authentication_required" }, status: :unauthorized }
      format.any { head :unauthorized }
    end
  end

  def deny_forbidden_access!
    respond_to do |format|
      format.html do
        redirect_to salary_book_path, alert: "You do not have access to that page."
      end
      format.json { render json: { error: "forbidden" }, status: :forbidden }
      format.any { head :forbidden }
    end
  end

  def store_return_location!
    return unless request.get?
    return unless request.format.html?
    return if request.path == login_path

    session[:return_to] = request.fullpath
  end

  def consume_return_location
    raw_path = session.delete(:return_to).to_s
    return nil if raw_path.blank?
    return nil unless raw_path.start_with?("/")
    return nil if raw_path.start_with?("/login")
    return nil if raw_path.start_with?("/logout")

    raw_path
  end

  def auth_bypassed_for_localhost?
    localhost_host?
  end

  def localhost_host?
    host = request.host.to_s.strip.downcase
    LOCALHOST_HOSTS.include?(host) || host.ends_with?(".localhost")
  end
end

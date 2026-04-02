class ApplicationController < ActionController::Base
  before_action :authenticate_user!
  before_action :check_temp_password
  before_action :set_semesters

  # Catch all CanCanCan AccessDenied errors
  rescue_from CanCan::AccessDenied do |exception|
    respond_to do |format|
      format.html do
        flash[:alert] = "You are not authorized to access this page."
        redirect_to root_path
      end
      format.json { render json: { error: "You are not authorized to access this page." }, status: :forbidden }
      format.js { head :forbidden }
    end
  end

  private

  def set_semesters
    @semesters = Semester.all
  end

  def check_temp_password
    return unless user_signed_in?
    return if current_user.temp_password_changed?
    return if controller_name == 'forced_password_changes'

    redirect_to forced_password_change_path,
      alert: "You must set a new password before continuing."
  end
end

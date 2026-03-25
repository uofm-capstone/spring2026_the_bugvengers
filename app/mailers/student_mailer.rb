class StudentMailer < ApplicationMailer

  # Subject can be set in your I18n file at config/locales/en.yml
  # with the following lookup:
  #
  #   en.student_mailer.welcome_email.subject
  #
  def welcome_email(user, temp_password)
    @user = user
    @temp_password = temp_password
    @login_url = new_user_session_url

    mail(to: @user.email, subject: "Welcome to TAG")
  end
end

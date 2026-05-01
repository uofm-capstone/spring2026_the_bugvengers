class KanbanMonkeyMailer < ApplicationMailer
  def commit_reminder(user, student, sprint, team)
    @user    = user
    @student = student
    @sprint  = sprint
    @team    = team

    mail(to: @user.email, subject: "TAG Reminder — no commits recorded for #{@sprint.name}")
  end
end
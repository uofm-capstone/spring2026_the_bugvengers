class TeamRegistrationsController < ApplicationController
  skip_before_action :authenticate_user!
  skip_authorization_check

  def new
    @team = Team.new
    @semesters = Semester.all
  end

  def create
    @team = Team.new(team_params)

    if @team.save
      if current_user&.guest?
        current_user.update!(role: :student)

        student = Student.find_or_create_by(email: current_user.email, semester_id: @team.semester_id) do |s|
          s.full_name = current_user.email
        end

        StudentTeam.create!(team: @team, student: student)
      end

      redirect_to root_path, notice: "Team registration submitted successfully."
    else
      @semesters = Semester.all
      render :new, status: :unprocessable_entity
    end
  end

  def team_params
    params.require(:team).permit(
      :name,
      :description,
      :semester_id,
      :repo_url,
      :timesheet_url,
      :project_board_url,
      :client_notes_url
    )
  end
end

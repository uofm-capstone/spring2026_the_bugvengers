# app/controllers/semesters_controller.rb
class SemestersController < ApplicationController
  require 'text'
  helper_method :get_client_score
  helper_method :team_exist
  helper_method :get_flags
  helper_method :unfinished_sprint

  include PreprocessorHelper
  include TeamsHelper
  include SprintsHelper
  include ClientScoreHelper
  include ClientDisplayHelper
  include ClientSurveyPatternsHelper

  before_action :set_semester, only: [:show, :edit, :update, :destroy]
  before_action :check_ownership, only: [:destroy]
  before_action :check_admin

  # --------------------------------------------------------
  # SETUP & AUTHORIZATION HELPERS
  # --------------------------------------------------------

  # Finds the semester record by ID before certain actions.
  def set_semester
    @semester = Semester.find(params[:id])
  end

  # Restricts deletion to the semester's creator or an admin.
  def check_ownership
    unless current_user == @semester.user || current_user.admin?
      redirect_to(semesters_path, alert: "You are not authorized to perform this action.")
    end
  end

  # Restricts accessing semesters to admin users.
  def check_admin
    unless current_user.admin?
      redirect_to root_path(flash[:alert] = "You are not authorized to access this page.")
    end
  end

  # --------------------------------------------------------
  # INDEX / HOME
  # --------------------------------------------------------

  def select
    @semester = Semester.find(params[:id])
    session[:last_viewed_semester_id] = @semester.id
    redirect_to semesters_path, notice: "Semester selected."
  end

  # Displays all semesters on the main Semesters page.
  def home
    @semesters = Semester.order(:year)
    render :home
  end

  # --------------------------------------------------------
  # SHOW PAGE
  # --------------------------------------------------------

  # Displays semester details, including teams and sprint data.
  def show
    session[:return_to] ||= request.referer
    @semester = Semester.find(params[:id])

    # Store the current semester in the session.
    session[:last_viewed_semester_id] = @semester.id

    # Load all teams and sprint info.
    @teams = @semester.teams
    @sprint_list = @semester.sprints.pluck(:name)
    @flags = {}

    # Build flags data per sprint and team for status display.
    @sprint_list.each do |sprint|
      @flags[sprint] = {}
      @teams.each do |team|
        @flags[sprint][team.name] = get_flags(@semester, sprint, team.name)
      end
    end

    # Load repository and sprint info for display.
    @repos = current_user.repositories
    @sprints = @semester.sprints
    @start_dates, @end_dates, @team_names, @repo_owners, @repo_names, @access_tokens, @sprint_numbers = get_git_info(@semester)

    render :show
  end

  # --------------------------------------------------------
  # NEW / CREATE SEMESTER
  # --------------------------------------------------------

  # Renders the "New Semester" form.
  def new
    @semester = Semester.new

    # Prefill semester/year from params if coming from redirect.
    @semester.semester = params[:semester] if params[:semester]
    @semester.year = params[:year] if params[:year]
    render :new
  end

  # Handles form submission for creating a new semester.
  # Automatically imports students and teams from uploaded CSV.
  # def create
  #   @semester = current_user.semester.build(semester: params[:semester], year: params[:year])

  #   # Attach uploaded CSV files if present.
  #   @semester.student_csv.attach(params[:student_csv]) if params[:student_csv].present?
  #   @semester.client_csv.attach(params[:client_csv])   if params[:client_csv].present?
  #   @semester.git_csv.attach(params[:git_csv])         if params[:git_csv].present?

  #   if @semester.save
  #     # Import Student CSV (creates students + teams).
  #     if @semester.student_csv.attached?
  #       unless @semester.import_students_from_csv
  #         flash.now[:alert] = @semester.errors.full_messages.join(", ")
  #         render :new, status: :unprocessable_entity and return
  #       end
  #     end

  #     redirect_to semesters_path, notice: "Semester created successfully and students imported."
  #   else
  #     flash.now[:error] = "Semester creation failed."
  #     render :new, status: :unprocessable_entity
  #   end
  # end
# def create
#   @semester = current_user.semester.build(semester: params[:semester], year: params[:year])

#   # Attach uploaded CSV files if present.
#   @semester.student_csv.attach(params[:student_csv]) if params[:student_csv].present?
#   @semester.client_csv.attach(params[:client_csv])   if params[:client_csv].present?
#   @semester.git_csv.attach(params[:git_csv])         if params[:git_csv].present?

#   if @semester.save
#     # Import Student CSV (creates students + teams).
#     if @semester.student_csv.attached?
#       @semester.import_students_from_csv

#       # 🔥 ALWAYS show import summary (success OR errors)
#       flash[:notice] = @semester.errors.full_messages.join("<br>").html_safe
#     end

#     redirect_to semesters_path, notice: "Semester created successfully and students imported."
#   else
#     flash.now[:error] = "Semester creation failed."
#     render :new, status: :unprocessable_entity
#   end
# end
# def create
#   @semester = current_user.semester.build(semester: params[:semester], year: params[:year])

#   # Attach uploaded CSV files
#   @semester.student_csv.attach(params[:student_csv]) if params[:student_csv].present?
#   @semester.client_csv.attach(params[:client_csv])   if params[:client_csv].present?
#   @semester.git_csv.attach(params[:git_csv])         if params[:git_csv].present?

#   if @semester.save
#     # Import CSV if attached
#     if @semester.student_csv.attached?
#       @semester.import_students_from_csv

#       if @semester.errors.any?
#         flash[:alert] = @semester.errors.full_messages.join("<br>").html_safe
#       else
#         flash[:notice] = "Students imported successfully."
#       end
#     end

#     flash[:success] = "Semester created successfully and students imported."
#     redirect_to semesters_path

#   else
#     flash.now[:error] = "Semester creation failed."
#     render :new, status: :unprocessable_entity
#   end
# end

def create
  @semester = current_user.semester.build(semester: params[:semester], year: params[:year])

  # Attach uploaded CSVs
  @semester.student_csv.attach(params[:student_csv]) if params[:student_csv].present?
  @semester.client_csv.attach(params[:client_csv])   if params[:client_csv].present?
  @semester.git_csv.attach(params[:git_csv])         if params[:git_csv].present?

  if @semester.save
    if @semester.student_csv.attached?
      @semester.import_students_from_csv

      if @semester.errors.any?
        # 🔥 Show CSV error summary
        flash[:alert] = @semester.errors.full_messages.join("<br>").html_safe
      elsif @semester.instance_variable_get(:@import_summary).present?
        # 🔥 Show CSV success summary (NO errors)
        flash[:notice] = @semester.instance_variable_get(:@import_summary)
      end
    end

    # 🔥 Always show semester creation message
    flash[:success] = "Semester created successfully and students imported."
    redirect_to semesters_path

  else
    flash.now[:error] = "Semester creation failed."
    render :new, status: :unprocessable_entity
  end
end





  # --------------------------------------------------------
  # EDIT / UPDATE SEMESTER
  # --------------------------------------------------------

  # Renders the "Edit Semester" form.
  def edit
    session[:return_to] ||= request.referer
    @semester = Semester.find(params[:id])
    render :edit
  end

  # Updates semester info (semester, year, and CSV uploads).
  # Re-imports student CSV if a new one is uploaded.
  # def update
  #   @semester = Semester.find(params[:id])
  #   was_student_csv_attached = @semester.student_csv.attached?

  #   if @semester.update(params.require(:semester).permit(:semester, :year, :student_csv, :client_csv, :git_csv))
  #     # Import new CSV if just uploaded.
  #     if !was_student_csv_attached && @semester.student_csv.attached?
  #       unless @semester.import_students_from_csv
  #         flash.now[:alert] = @semester.errors.full_messages.join(", ")
  #         render :edit, status: :unprocessable_entity and return
  #       end
  #     end

  #     flash[:success] = "Semester was successfully updated!"
  #     redirect_to semester_url(@semester)
  #   else
  #     flash.now[:error] = "Semester update failed!"
  #     render :edit, status: :unprocessable_entity
  #   end
  # end
  def update
    @semester = Semester.find(params[:id])
    was_student_csv_attached = @semester.student_csv.attached?

    if @semester.update(params.require(:semester).permit(:semester, :year, :student_csv, :client_csv, :git_csv))

      # Only import if new CSV uploaded
      if !was_student_csv_attached && @semester.student_csv.attached?
        @semester.import_students_from_csv

        if @semester.errors.any?
          flash[:alert] = @semester.errors.full_messages.join("<br>").html_safe
        else
          flash[:notice] = "Students imported successfully."
        end
      end

      flash[:success] = "Semester was successfully updated!"
      redirect_to semester_url(@semester)


    else
      flash.now[:error] = "Semester update failed!"
      render :edit, status: :unprocessable_entity
    end
end
# def update
#   @semester = Semester.find(params[:id])
#   was_student_csv_attached = @semester.student_csv.attached?

#   if @semester.update(params.require(:semester).permit(:semester, :year, :student_csv, :client_csv, :git_csv))

#     # Only import if new CSV was uploaded
#     if !was_student_csv_attached && @semester.student_csv.attached?
#       @semester.import_students_from_csv

#       if @semester.errors.any?
#         flash[:alert] = @semester.errors.full_messages.join("<br>").html_safe
#       else
#         flash[:notice] = "Students imported successfully."
#       end
#     end

#     flash[:success] = "Semester was successfully updated!"
#     redirect_to semester_url(@semester)

#   else
#     flash.now[:error] = "Semester update failed!"
#     render :edit, status: :unprocessable_entity
#   end
# end



  # --------------------------------------------------------
  # DESTROY SEMESTER
  # --------------------------------------------------------

  # Deletes the selected semester record.
  def destroy
    @semester = Semester.find(params[:id])
    @semester.destroy
    flash[:success] = "Semester was successfully deleted"
    redirect_to semesters_path, status: :see_other
  end

  # --------------------------------------------------------
  # STATUS PAGE
  # --------------------------------------------------------

  # Displays semester progress status for all teams/sprints.
def status
  @semester = Semester.find_by(id: params[:id])
    return redirect_to(semesters_path) unless @semester

    session[:last_viewed_semester_id] = @semester.id

    @teams = @semester.teams
    @sprint_list = @semester.sprints.pluck(:name)
    @flags = {}

    @sprint_list.each do |sprint|
      @flags[sprint] = {}
      @teams.each do |team|
        @flags[sprint][team.name] = get_flags(@semester, sprint, team.name)
      end
    end

    @repos = current_user.repositories
    @sprints = @semester.sprints.order(:start_date)
    @start_dates, @end_dates, @team_names, @repo_owners, @repo_names, @access_tokens, @sprint_numbers = get_git_info(@semester)

    # Calculate metrics for display.
    @service = GithubService.new(user: current_user)

    @team_project_data = {}
    @team_board_health = {}
    @team_sprint_metrics = {}
    @team_status_overview = []
    @github_inspector = {}
    @status_metrics = {}

    @teams.each do |team|
      team_service = GithubService.new(team: team, user: current_user)
      board_health = team_service.board_health(team.project_board_url)
      project_cards = board_health.cards

      @team_project_data[team.id] = project_cards
      @team_board_health[team.id] = board_health
      @team_sprint_metrics[team.id] = {}
      @status_metrics[team.id] = {}

      repo_full_name = resolve_team_repo_full_name(team)
      sprint_commit_metrics = {}
      sprint_progress_metrics = {}
      inspector_sprints = {}

      @sprints.each do |sprint|
        if repo_full_name.present?
          sprint_commit_metrics[sprint.name] = team_service.commit_metrics_by_user(repo_full_name, sprint.start_date, sprint.end_date)
          progress_check_start = sprint.progress_deadline&.beginning_of_day || sprint.start_date
          sprint_progress_metrics[sprint.name] = team_service.commit_metrics_by_user(repo_full_name, progress_check_start, sprint.end_date)
        else
          sprint_commit_metrics[sprint.name] = {}
          sprint_progress_metrics[sprint.name] = {}
        end

        team_metric = build_team_sprint_metrics(
          team_cards: project_cards,
          board_health: board_health,
          sprint: sprint,
          sprint_commit_metric_map: sprint_commit_metrics[sprint.name],
          students: team.students
        )
        @team_sprint_metrics[team.id][sprint.name] = team_metric

        inspector_sprints[sprint.name] = {
          start_date: sprint.start_date,
          end_date: sprint.end_date,
          progress_deadline: sprint.progress_deadline,
          total_commits: team_metric[:team_commit_count],
          commit_authors: sprint_commit_metrics[sprint.name].keys.sort,
          students_without_commits: team_metric[:students_without_commits]
        }
      end

      team.students.each do |student|
        @status_metrics[team.id][student.id] = {}

        @sprints.each do |sprint|
          @status_metrics[team.id][student.id][sprint.name] = build_live_status_metrics(
            team_cards: project_cards,
            board_health: board_health,
            student: student,
            sprint: sprint,
            sprint_commit_metrics: sprint_commit_metrics,
            sprint_progress_metrics: sprint_progress_metrics
          )
        end
      end

      @team_status_overview << {
        team_id: team.id,
        team_name: team.name,
        students_count: team.students.count,
        any_at_risk: @team_sprint_metrics[team.id].values.any? { |metric| metric[:at_risk] },
        any_missing_sprint_done: @team_sprint_metrics[team.id].values.any? { |metric| metric[:missing_sprint_done] },
        at_risk_reason_preview: @team_sprint_metrics[team.id].values.flat_map { |metric| metric[:at_risk_reasons] }.uniq.first(2),
        sprint_metrics: @team_sprint_metrics[team.id]
      }

      @github_inspector[team.id] = {
        project_url: team.project_board_url,
        status_options: board_health.status_options,
        card_counts: @service.get_card_count_per_column(project_cards),
        repo_full_name: repo_full_name,
        sprint_payloads: inspector_sprints
      }
    end

    @team_overview_by_id = @team_status_overview.index_by { |summary| summary[:team_id] }

    render :show
end

  # --------------------------------------------------------
  # UPLOAD ADDITIONAL CSV FILES
  # --------------------------------------------------------

  # Handles Sprint CSV uploads (student/client data per sprint).
  def upload_sprint_csv
    @semester = Semester.find(params[:id])
    sprint_name = params[:sprint_name]

    @semester.student_csv.attach(params[:student_csv]) if params[:student_csv].present?
    @semester.client_csv.attach(params[:client_csv]) if params[:client_csv].present?

    flash[:notice] = "#{sprint_name} CSVs uploaded!"
    redirect_to semester_path(@semester)
  end

  # --------------------------------------------------------
  # HELPER / UTILITY METHODS
  # --------------------------------------------------------

  # Returns a list of all team names for a given semester.
  def getTeams(semester)
    semester.teams.pluck(:name)
  end

  # Builds flag indicators for teams on the status page.
  def get_flags(semester, sprint, team)
    flags = []
    begin
      semester.student_csv.open do |tempStudent|
        studentData = SmarterCSV.process(tempStudent.path)
        student_survey = studentData.find_all { |survey| survey[:q2] == team && survey[:q22] == sprint }
        flags.append("student blank") if student_survey.blank?
      end
    rescue => _e
      flags.append("no data")
    end
    flags
  end

  # Checks if any teams exist (used in views).
  def team_exist(arr)
    arr.length > 0
  end

  # Loads static student classlist CSV for older semesters (legacy feature).
  def classlist
    @semester = Semester.find(params[:id])
    filepath = Rails.root.join('lib', 'assets', 'Students_list.csv')
    @students_info = []

    CSV.foreach(filepath, headers: true) do |row|
      @students_info << { full_name: row['Name'], role: row['Role'] }
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to semesters_path, alert: 'Semester not found.'
  end

  # Determines if all teams for a sprint are marked "student blank".
  def unfinished_sprint(teams, flags, sprint)
    teams.each do |t|
      return false if flags[sprint][t] != ["student blank"]
    end
    true
  end

  def save_sprints
    @semester = Semester.find(params[:id])

    (1..4).each do |i|
      sprint_params = params["sprint_#{i}"]
      next unless sprint_params.present?

      sprint = @semester.sprints.find_or_initialize_by(name: "Sprint #{i}")

      sprint.assign_attributes(
        planning_deadline: parse_date(sprint_params[:planning_deadline]),
        progress_deadline: parse_date(sprint_params[:progress_deadline]),
        demo_deadline: parse_date(sprint_params[:demo_deadline])
      )

      sprint.save!
    end

    redirect_to semester_path(@semester), notice: "Sprint deadlines saved successfully."
  end

  # --------------------------------------------------------
  # PRIVATE METHODS
  # --------------------------------------------------------

  private

  def build_live_status_metrics(team_cards:, board_health:, student:, sprint:, sprint_commit_metrics:, sprint_progress_metrics:)
    cbp = cbp_metric_for_user(sprint_commit_metrics[sprint.name], student.github_username)
    tsp_commit = cbp_metric_for_user(sprint_progress_metrics[sprint.name], student.github_username)

    stale_assigned_cards = board_health.stale_cards.count do |card|
      card.assignees.include?(student.github_username)
    end

    columns = @service.get_card_count_per_column(team_cards)
    sprint_done_count = team_cards.count { |card| done_in_sprint_status?(card.status, sprint.name) }
    done_in_any_sprint_count = team_cards.count { |card| done_in_any_sprint_status?(card.status) }
    current_board_done_count = columns["Done"]
    archived_count = columns["Archived"]
    active_now_count = columns["Backlog"] + columns["Todo"] + columns["To Do"] + columns["In Progress"]
    total_count = columns.values.sum

    {
      ku: {
        archived_column_exists: board_health.archived_column_exists,
        stale_team_tasks: board_health.stale_cards.count
      },
      pp: {
        current_board_done_cards: current_board_done_count,
        sprint_done_cards: sprint_done_count,
        done_in_any_sprint_cards: done_in_any_sprint_count,
        archived_cards: archived_count,
        active_now_cards: active_now_count,
        total_cards: total_count
      },
      cbp: cbp,
      tsp: {
        commit_count_since_progress: tsp_commit.commit_count,
        lines_changed_since_progress: tsp_commit.lines_changed,
        stale_assigned_tasks: stale_assigned_cards
      }
    }
  end

  def build_team_sprint_metrics(team_cards:, board_health:, sprint:, sprint_commit_metric_map:, students:)
    columns = @service.get_card_count_per_column(team_cards)
    sprint_done_count = team_cards.count { |card| done_in_sprint_status?(card.status, sprint.name) }
    done_in_any_sprint_count = team_cards.count { |card| done_in_any_sprint_status?(card.status) }
    current_board_done_count = columns["Done"]
    archived_count = columns["Archived"]
    active_now_count = columns["Backlog"] + columns["Todo"] + columns["To Do"] + columns["In Progress"]
    total_count = columns.values.sum

    students_without_commits = students.filter_map do |student|
      next if student.github_username.blank?

      commit_metric = cbp_metric_for_user(sprint_commit_metric_map, student.github_username)
      student.github_username if commit_metric.commit_count.zero?
    end

    risk_reasons = []
    risk_reasons << "No cards in Done in #{sprint.name}" if sprint_done_count.zero?
    if students_without_commits.any?
      risk_reasons << "#{students_without_commits.count}/#{students.count} students have 0 commits"
    end

    {
      sprint_name: sprint.name,
      archived_column_exists: board_health.archived_column_exists,
      current_board_done_cards: current_board_done_count,
      sprint_done_cards: sprint_done_count,
      done_in_any_sprint_cards: done_in_any_sprint_count,
      archived_cards: archived_count,
      active_now_cards: active_now_count,
      total_cards: total_count,
      missing_sprint_done: sprint_done_count.zero?,
      students_without_commits: students_without_commits,
      team_commit_count: sprint_commit_metric_map.values.sum(&:commit_count),
      at_risk: risk_reasons.any?,
      at_risk_reasons: risk_reasons
    }
  end

  def cbp_metric_for_user(metrics_by_user, username)
    return GithubService::CBPResult.new(0, 0, 0, 0) if username.blank? || metrics_by_user.blank?

    exact = metrics_by_user[username]
    return exact if exact.present?

    metrics_by_user.each do |author, metric|
      return metric if author.to_s.casecmp(username.to_s).zero?
    end

    GithubService::CBPResult.new(0, 0, 0, 0)
  end

  def done_in_sprint_status?(status, sprint_name)
    return false if status.blank? || sprint_name.blank?

    sprint_number = sprint_name.to_s[/\d+/]
    return false if sprint_number.blank?

    normalized = status.to_s.strip.downcase
    normalized.match?(/\Adone in sprint\s*#{Regexp.escape(sprint_number)}\z/)
  end

  def done_in_any_sprint_status?(status)
    return false if status.blank?

    status.to_s.strip.downcase.match?(/\Adone in sprint\s*\d+\z/)
  end

  def resolve_team_repo_full_name(team)
    parsed_repo = @service.parse_repo_url(team.repo_url)
    return parsed_repo if parsed_repo.present?

    repository = @semester.repositories.find_by(team_id: team.id)
    repository ||= @semester.repositories.find_by(team: team.name)

    if repository&.owner.present? && repository&.repo_name.present?
      return "#{repository.owner}/#{repository.repo_name}"
    end

    csv_owner = @repo_owners[team.name]
    csv_repo = @repo_names[team.name]
    return nil if csv_owner.blank? || csv_repo.blank?

    "#{csv_owner}/#{csv_repo}"
  end

  def parse_date(value)
    value.present? ? Date.parse(value) : nil
  rescue ArgumentError
    nil
  end

  # Permits only the allowed semester params for strong parameter safety.
  def semester_params
    params.permit(
      :semester, :year, :sprint_number,
      sprints_attributes: [:id, :_destroy, :start_date, :end_date],
      student_csv: [], client_csv: [], git_csv: []
    )
  end
end

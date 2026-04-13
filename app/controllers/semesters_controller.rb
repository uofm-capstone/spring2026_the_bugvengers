# app/controllers/semesters_controller.rb
class SemestersController < ApplicationController
  require 'text'
  require 'timeout'
  GITHUB_SCORE_WEIGHTS = {
    kanban: 0.35,
    cbp: 0.30,
    pr: 0.20,
    review: 0.15
  }.freeze

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

  before_action :set_semester, only: [:show, :edit, :update, :destroy, :sponsor_responses, :upload_sponsor_csv, :sponsor_response_details]
  before_action :check_ownership, only: [:destroy]
  before_action :check_admin
  before_action :check_ta_or_admin, only: [:sponsor_responses, :upload_sponsor_csv, :sponsor_response_details]
  skip_before_action :check_admin, only: [:sponsor_responses, :upload_sponsor_csv, :sponsor_response_details]

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

  # Allows access for TA and Admin users.
  def check_ta_or_admin
    unless current_user&.ta? || current_user&.admin?
      redirect_to semesters_path, alert: "Access denied."
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
    render :show
  end

  # Returns heavy status content after shell has rendered.
  def status_content
    @semester = Semester.find_by(id: params[:id])
    return head :not_found unless @semester

    session[:last_viewed_semester_id] = @semester.id

    build_status_payload!
    @show_github_inspector = current_user.admin? && params[:debug] == "github"

    render partial: "semesters/status_content"
  rescue StandardError => e
    Rails.logger.error("Status content build failed for semester #{params[:id]}: #{e.class} - #{e.message}")
    render partial: "semesters/status_content_timeout"
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

  # Sponsor response upload + summary UI page.
  def sponsor_responses
    @sponsor_csv_attached = @semester.client_csv.attached?
    @sponsor_rows_count = 0
    @sponsor_summary_text = "Upload a sponsor CSV to generate a summary. Once backend AI summarization is wired, this popup will show the LLM output."

    return unless @sponsor_csv_attached

    parsed = parse_sponsor_csv
    @sponsor_rows_count = parsed[:rows].size

    if parsed[:errors].present?
      @sponsor_summary_text = "Sponsor CSV is attached, but parsing failed. Please verify CSV format and try again."
      flash.now[:alert] = parsed[:errors].join(" | ")
      return
    end

    @sponsor_summary_text = "Placeholder summary: #{@sponsor_rows_count} sponsor responses parsed across teams and sprints. Backend AI summary output will appear here once connected."
  end

  # Handles sponsor CSV upload from the frontend form.
  def upload_sponsor_csv
    sprint_number = params[:sprint_number].to_s.strip
    sprint_label = "Sprint #{sprint_number}"
    sprint_key = "sprint-#{sprint_number}"
    attachment_name = sponsor_attachment_name_for_sprint(sprint_number)
    summary_override_text = nil
    success = false
    message = nil

    if attachment_name.nil?
      message = "Invalid sprint for sponsor CSV upload."
    elsif params[:sponsor_csv].present?
      attachment = @semester.public_send(attachment_name)
      attachment.attach(params[:sponsor_csv])
      success = attachment.attached?
      message = success ? "#{sprint_label} sponsor CSV uploaded successfully." : "#{sprint_label} sponsor CSV upload failed."

      # Important behavior contract for the status page:
      # run summary analysis only when the user explicitly uploads a CSV.
      # We never trigger LLM analysis from page-load rendering paths.
      if success
        summary_result = generate_sponsor_summary(sprint_number: sprint_number)

        # Without persistence, the current request must carry the generated
        # summary into modal rendering. This applies to both success and
        # fallback outputs so users always see immediate upload feedback.
        summary_override_text = summary_result[:summary_text]

        unless summary_result[:ok]
          # Keep upload successful even when LLM fails so teams do not lose CSV data.
          # The fallback summary gives immediate UI feedback and can be overwritten
          # by a future re-upload once the LLM endpoint is healthy.
          message = "#{sprint_label} sponsor CSV uploaded, but summary generation had a warning: #{summary_result[:message]}"
        end
      end
    else
      message = "Please choose a CSV file before uploading."
    end

    # Upload response can include one-off summary text for this request only.
    # This keeps summary rendering transient and avoids cross-page persistence.
    @sponsor_summary_overrides = { sprint_label => summary_override_text }
    build_sponsor_ui_payload!

    respond_to do |format|
      format.json do
        modals_html = render_to_string(partial: "semesters/sponsor_response_modals", formats: [:html])
        render json: {
          success: success,
          message: message,
          modals_html: modals_html,
          sponsor_csv_attached: @sponsor_csv_attached,
          sprint_key: sprint_key
        }, status: (success ? :ok : :unprocessable_entity)
      end

      format.html do
        flash[success ? :notice : :alert] = message
        redirect_to semester_path(@semester)
      end
    end
  end

  # Dedicated sponsor detail page with question/answer rows.
  def sponsor_response_details
    @sponsor_csv_attached = @semester.client_csv.attached?
    @sponsor_details = []

    return unless @sponsor_csv_attached

    parsed = parse_sponsor_csv
    if parsed[:errors].present?
      flash.now[:alert] = parsed[:errors].join(" | ")
      return
    end

    @sponsor_details = build_sponsor_details(parsed: parsed)
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

    begin
      semester.client_csv.open do |tempClient|
        # Reuse the centralized parser so status flags follow the same CSV rules as team/detail views.
        parsed = CSVSurveyParserService.new(file: tempClient).parse
        if parsed[:errors].present?
          flags.append("client csv error")
          next
        end

        client_rows = parsed[:rows]
        next if client_rows.blank?

        # Uses fuzzy team matching scoped to sprint to mirror team page behavior.
        team_rows = best_matching_team_rows(client_rows: client_rows, team: team, sprint: sprint)
        flags.append("client blank") if team_rows.blank?
      end
    rescue => e
      Rails.logger.debug("DEBUG: Exception processing client flags CSV: #{e}")
      flags.append("client csv error")
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

  # --------------------------------------------------------
  # PRIVATE METHODS
  # --------------------------------------------------------

  private

  def parse_sponsor_csv(attachment: nil)
    target_attachment = attachment || @semester.client_csv
    return { rows: [], full_questions: {}, errors: ["No sponsor CSV attached."] } unless target_attachment&.attached?

    target_attachment.open do |temp_client|
      CSVSurveyParserService.new(file: temp_client).parse
    end
  rescue StandardError => e
    Rails.logger.error("Sponsor CSV parse failed for semester #{@semester.id}: #{e.class} - #{e.message}")
    { rows: [], full_questions: {}, errors: ["Unable to parse sponsor CSV."] }
  end

  def sponsor_attachment_name_for_sprint(sprint_number)
    case sprint_number.to_s
    when "2"
      :sponsor_csv_sprint_2
    when "3"
      :sponsor_csv_sprint_3
    when "4"
      :sponsor_csv_sprint_4
    end
  end

  # Executes parse + LLM summary generation through SponsorSummaryService.
  # Summary storage is handled separately in session-scoped cache helpers.
  def generate_sponsor_summary(sprint_number:)
    SponsorSummaryService.new(semester: @semester, sprint_number: sprint_number).generate
  rescue StandardError => e
    Rails.logger.error("Sponsor summary generation failed for semester #{@semester.id}: #{e.class} - #{e.message}")

    {
      ok: false,
      summary_text: SponsorSummaryService::FALLBACK_SUMMARY_TEXT,
      message: "Summary generation failed after upload."
    }
  end

  def build_sponsor_details(parsed:)
    rows = parsed[:rows] || []
    full_questions = parsed[:full_questions] || {}
    detail_keys = rows.first&.keys&.select { |key| key.to_s.match?(/\Aq2_\d+\z/i) || %w[q4 q5 q6 q7].include?(key.to_s.downcase) } || []

    rows.map do |row|
      responses = detail_keys.map do |key|
        # Prefer descriptive prompt text from parser map; keep resilient fallbacks
        # for older CSV formats where prompt metadata may be incomplete.
        question_key = key.to_s
        question = full_questions[question_key].presence || full_questions[question_key.downcase].presence || key.to_s.upcase
        raw_answer = row[key].to_s.strip
        answer_text = raw_answer.presence || "Not answered"

        # Qualtrics q2_* prompts are often shaped like:
        # "Please evaluate ... - The team was on time ..."
        # For table readability, keep the shared prompt in the Question column
        # and move the statement-specific clause to the Answer column.
        if question_key.match?(/\Aq2_\d+\z/i) && question.include?(" - ")
          base_prompt, criterion = question.split(/\s+-\s+/, 2)

          if base_prompt.present? && criterion.present?
            question = base_prompt.strip
            answer_text = "#{criterion.strip}: #{answer_text}"
          end
        end

        { question: question, answer: answer_text }
      end

      {
        team: row[:q1_team].presence || "Unknown Team",
        sprint: row[:q3].presence || "Unknown Sprint",
        responses: responses
      }
    end
  end

  def build_status_payload!
    @teams = @semester.teams
    @sprint_list = @semester.sprints.pluck(:name)
    @flags = {}

    @sprint_list.each do |sprint|
      @flags[sprint] = {}
      @teams.each do |team|
        @flags[sprint][team.name] = get_flags(@semester, sprint, team.name)
      end
    end

    @sprints = @semester.sprints.order(:start_date)

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
      board_health = safe_board_health(team_service: team_service, team: team)
      project_cards = board_health.cards
      repo = team_service.parse_repo_url(team.repo_url)
      sprint_cards_by_name = {}
      github_metrics_by_sprint = {}

      @team_project_data[team.id] = project_cards
      @team_board_health[team.id] = board_health
      @team_sprint_metrics[team.id] = {}
      @status_metrics[team.id] = {}

      inspector_sprints = {}

      @sprints.each do |sprint|
        sprint_cards = cards_for_sprint(project_cards, sprint)
        sprint_cards_by_name[sprint.name] = sprint_cards

        github_metrics = safe_github_sprint_metrics(
          team_service: team_service,
          repo: repo,
          sprint: sprint,
          students: team.students,
          team: team
        )
        github_metrics_by_sprint[sprint.name] = github_metrics

        team_metric = build_team_sprint_metrics(
          sprint_cards: sprint_cards,
          board_health: board_health,
          sprint: sprint,
          students: team.students,
          github_metrics: github_metrics
        )
        @team_sprint_metrics[team.id][sprint.name] = team_metric

        inspector_sprints[sprint.name] = {
          start_date: sprint.start_date,
          end_date: sprint.end_date,
          progress_deadline: sprint.progress_deadline,
          total_cards: team_metric[:total_cards],
          total_estimate: team_metric[:estimated_hours],
          total_spent: team_metric[:time_spent_hours],
          cards_missing_spent: team_metric[:cards_missing_time_spent],
          github_repo: repo,
          github_scores: team_metric[:github],
          card_time_samples: sprint_cards.map { |card| card_time_sample(card) }
        }
      end

      team.students.each do |student|
        @status_metrics[team.id][student.id] = {}

        @sprints.each do |sprint|
          sprint_github_metrics = github_metrics_by_sprint[sprint.name] || {}
          @status_metrics[team.id][student.id][sprint.name] = build_live_status_metrics(
            sprint_cards: sprint_cards_by_name[sprint.name],
            board_health: board_health,
            student: student,
            sprint: sprint,
            github_student_metrics: sprint_github_metrics.dig(:per_student, student.github_username),
            team_missing_data_flags: sprint_github_metrics[:missing_data_flags],
            team_github_available: sprint_github_metrics[:data_available]
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
        sprint_payloads: inspector_sprints
      }
    end

    @team_overview_by_id = @team_status_overview.index_by { |summary| summary[:team_id] }
    build_sponsor_ui_payload!
    build_sponsor_scores_by_team!
  end

  def build_sponsor_scores_by_team!
    sprint_sources = {
      "Sprint 2" => @semester.sponsor_csv_sprint_2,
      "Sprint 3" => @semester.sponsor_csv_sprint_3,
      "Sprint 4" => @semester.sponsor_csv_sprint_4
    }

    @sponsor_scores_by_team = @teams.each_with_object({}) do |team, acc|
      acc[team.name] = {
        "Sprint 2" => nil,
        "Sprint 3" => nil,
        "Sprint 4" => nil
      }
    end

    sprint_sources.each do |sprint_label, attachment|
      next unless attachment.attached?

      parsed = parse_sponsor_csv(attachment: attachment)
      rows = parsed[:rows] || []
      next if parsed[:errors].present? || rows.blank?

      performance_columns = rows.first.keys.select { |header| header.to_s.match?(PERFORMANCE_PATTERN) }

      @teams.each do |team|
        matching_rows = best_matching_team_rows(client_rows: rows, team: team.name, sprint: sprint_label)
        next if matching_rows.blank? || performance_columns.blank?

        @sponsor_scores_by_team[team.name][sprint_label] = calculate_score(matching_rows.first, performance_columns)
      end
    end
  end

  def build_sponsor_ui_payload!
    sponsor_sources = {
      "Sprint 2" => @semester.sponsor_csv_sprint_2,
      "Sprint 3" => @semester.sponsor_csv_sprint_3,
      "Sprint 4" => @semester.sponsor_csv_sprint_4
    }

    @sponsor_csv_attached = {}
    @sponsor_rows_count = {}
    @sponsor_summary_text = {}
    @sponsor_details = {}

    sponsor_sources.each do |sprint_label, attachment|
      override_summary = @sponsor_summary_overrides&.[](sprint_label)

      @sponsor_csv_attached[sprint_label] = attachment.attached?
      @sponsor_rows_count[sprint_label] = 0
      @sponsor_summary_text[sprint_label] = "Upload a sponsor CSV for #{sprint_label} to view summary and detailed questions."
      @sponsor_details[sprint_label] = []

      next unless attachment.attached?

      parsed = parse_sponsor_csv(attachment: attachment)
      @sponsor_rows_count[sprint_label] = parsed[:rows].size

      if parsed[:errors].present?
        @sponsor_summary_text[sprint_label] = "#{sprint_label} sponsor CSV is attached, but parsing failed. Please verify CSV format and try again."
        next
      end

      # Summary display precedence:
      # 1) upload-time override for this request (typically LLM warning fallback)
      # 2) explicit waiting message when a CSV exists but summary is not part
      #    of the current request lifecycle.
      @sponsor_summary_text[sprint_label] = if override_summary.present?
                                              override_summary
                                            else
                                              "#{sprint_label} sponsor CSV uploaded. Summary has not been generated yet. Re-upload to retry analysis."
                                            end
      @sponsor_details[sprint_label] = build_sponsor_details(parsed: parsed)
    end
  end

  def safe_board_health(team_service:, team:)
    Timeout.timeout(10) do
      team_service.board_health(team.project_board_url)
    end
  rescue Timeout::Error
    Rails.logger.warn("Board health query timed out for team #{team.id}")
    GithubService::BoardHealth.new([], [], false, [])
  rescue StandardError => e
    Rails.logger.warn("Board health query failed for team #{team.id}: #{e.class} - #{e.message}")
    GithubService::BoardHealth.new([], [], false, [])
  end

  def safe_github_sprint_metrics(team_service:, repo:, sprint:, students:, team:)
    Timeout.timeout(8) do
      build_github_sprint_metrics(
        team_service: team_service,
        repo: repo,
        sprint: sprint,
        students: students
      )
    end
  rescue Timeout::Error
    Rails.logger.warn("GitHub sprint metrics timed out for team #{team.id}, sprint #{sprint.name}")
    empty_team_github_metrics(repo: repo, missing_data_flags: ["github_query_timeout"])
  rescue StandardError => e
    Rails.logger.warn("GitHub sprint metrics failed for team #{team.id}, sprint #{sprint.name}: #{e.class} - #{e.message}")
    empty_team_github_metrics(repo: repo, missing_data_flags: ["github_query_failed"])
  end

  def build_live_status_metrics(
    sprint_cards:,
    board_health:,
    student:,
    sprint:,
    github_student_metrics: nil,
    team_missing_data_flags: nil,
    team_github_available: nil
  )
    columns = @service.get_card_count_per_column(sprint_cards)
    sprint_done_count = sprint_cards.count { |card| done_in_sprint_status?(card.status, sprint.name) }
    done_in_any_sprint_count = sprint_cards.count { |card| done_in_any_sprint_status?(card.status) }
    current_board_done_count = columns["Done"]
    archived_count = columns["Archived"]
    active_now_count = columns["Backlog"] + columns["Todo"] + columns["To Do"] + columns["In Progress"]
    total_count = columns.values.sum

    per_student_column_counts = Hash.new(0)
    assigned_card_count = 0
    estimated_hours = 0
    time_spent_hours = 0

    sprint_cards.each do |card|
      next unless card.assignees.include?(student.github_username)

      assigned_card_count += 1
      status = card.status || "Unspecified"
      per_student_column_counts[status] += 1
      estimated_hours += estimate_value(card)
      time_spent_hours += spent_value(card)
    end

    done_status_total = per_student_column_counts["Done"] + per_student_column_counts["Archived"] +
                        per_student_column_counts.select { |status_name, _count| done_in_any_sprint_status?(status_name) }.values.sum

    student_done_scope_cards = sprint_cards.select do |card|
      next false unless card.assignees.include?(student.github_username)

      status = card.status.to_s
      done_in_any_sprint_status?(status) || status.casecmp("Done").zero? || status.casecmp("Archived").zero?
    end
    student_done_scope_count = student_done_scope_cards.size
    student_done_with_estimate_pct = percentage(
      student_done_scope_cards.count { |card| estimate_value(card).positive? },
      student_done_scope_count
    )
    student_done_with_time_taken_pct = percentage(
      student_done_scope_cards.count { |card| spent_value(card).positive? },
      student_done_scope_count
    )
    # KU focuses on documentation hygiene for completed student work.
    student_kanban_score = (
      (assigned_card_count.positive? ? 20.0 : 0.0) +
      (student_done_with_estimate_pct * 0.40) +
      (student_done_with_time_taken_pct * 0.40)
    ).round(1)
    student_kanban_band = assigned_card_count.zero? ? "No Data" : ku_band_for(student_kanban_score)

    student_pp_completion_pct = percentage(done_status_total, assigned_card_count).round(1)
    student_pp_band = assigned_card_count.zero? ? "No Data" : pp_band_for(student_pp_completion_pct)

    if github_student_metrics.blank?
      inferred_flags = Array(team_missing_data_flags).presence || ["github_student_data_unavailable"]
      github_student_metrics = empty_student_github_metrics(
        missing_data_flags: inferred_flags,
        data_available: team_github_available
      )
    end
    cbp_data = github_student_metrics[:cbp] || {}
    pr_data = github_student_metrics[:pr] || {}
    review_data = github_student_metrics[:review] || {}
    missing_data_flags = Array(github_student_metrics[:missing_data_flags])

    cbp_score = score_cbp(
      commit_count: cbp_data[:commit_count].to_i,
      lines_changed: cbp_data[:lines_changed].to_i
    )
    pr_score = score_pr(
      opened_count: pr_data[:opened_count].to_i,
      merged_count: pr_data[:merged_count].to_i,
      open_count: pr_data[:open_count].to_i,
      avg_merge_hours: pr_data[:avg_merge_hours].to_f
    )
    review_score = score_review(
      review_count: review_data[:review_count].to_i,
      approvals: review_data[:approvals].to_i,
      changes_requested: review_data[:changes_requested].to_i
    )
    has_non_kanban_github_data = (
      cbp_data[:commit_count].to_i.positive? ||
      pr_data[:opened_count].to_i.positive? ||
      review_data[:review_count].to_i.positive?
    )

    github_score = (
      (student_kanban_score * GITHUB_SCORE_WEIGHTS[:kanban]) +
      (cbp_score * GITHUB_SCORE_WEIGHTS[:cbp]) +
      (pr_score * GITHUB_SCORE_WEIGHTS[:pr]) +
      (review_score * GITHUB_SCORE_WEIGHTS[:review])
    ).round(1)
    github_band = if assigned_card_count.zero? && !has_non_kanban_github_data
      "No Data"
    else
      github_band_for(github_score)
    end

    {
      fsd: {
        backlog: per_student_column_counts["Backlog"],
        todo: per_student_column_counts["Todo"] + per_student_column_counts["To Do"],
        in_progress: per_student_column_counts["In Progress"],
        done: done_status_total
      },
      fa: {
        assigned_cards: assigned_card_count
      },
      te: {
        estimated_hours: estimated_hours.round(1)
      },
      ts: {
        time_spent_hours: time_spent_hours.round(1)
      },
      ku: {
        score: student_kanban_score,
        band: student_kanban_band
      },
      pp: {
        current_board_done_cards: current_board_done_count,
        sprint_done_cards: sprint_done_count,
        done_in_any_sprint_cards: done_in_any_sprint_count,
        archived_cards: archived_count,
        active_now_cards: active_now_count,
        total_cards: total_count,
        completion_pct: student_pp_completion_pct,
        band: student_pp_band
      },
      cbp: cbp_data,
      pr: pr_data,
      review: review_data,
      github: {
        score: github_score,
        band: github_band,
        cbp_score: cbp_score,
        pr_score: pr_score,
        review_score: review_score,
        kanban_score: student_kanban_score,
        data_available: github_student_metrics[:data_available],
        missing_data_flags: missing_data_flags
      }
    }
  end

  def build_team_sprint_metrics(sprint_cards:, board_health:, sprint:, students:, github_metrics: nil)
    columns = @service.get_card_count_per_column(sprint_cards)
    sprint_done_count = sprint_cards.count { |card| done_in_sprint_status?(card.status, sprint.name) }
    done_in_any_sprint_count = sprint_cards.count { |card| done_in_any_sprint_status?(card.status) }
    current_board_done_count = columns["Done"]
    archived_count = columns["Archived"]
    active_now_count = columns["Backlog"] + columns["Todo"] + columns["To Do"] + columns["In Progress"]
    total_count = columns.values.sum

    estimated_hours = sprint_cards.sum { |card| estimate_value(card) }
    time_spent_hours = sprint_cards.sum { |card| spent_value(card) }
    cards_missing_time_spent = sprint_cards.count do |card|
      done_in_any_sprint_status?(card.status) && spent_value(card).zero?
    end
    in_current_sprint = sprint_in_progress?(sprint)

    done_status_total = columns["Done"] + columns["Archived"] +
                        columns.select { |status_name, _count| done_in_any_sprint_status?(status_name) }.values.sum

    done_scope_cards = sprint_cards.select do |card|
      status = card.status.to_s
      done_in_any_sprint_status?(status) || status.casecmp("Done").zero? || status.casecmp("Archived").zero?
    end

    done_scope_count = done_scope_cards.size
    done_with_estimate_count = done_scope_cards.count { |card| estimate_value(card).positive? }
    done_with_time_taken_count = done_scope_cards.count { |card| spent_value(card).positive? }
    done_with_estimate_pct = percentage(done_with_estimate_count, done_scope_count)
    done_with_time_taken_pct = percentage(done_with_time_taken_count, done_scope_count)

    ku_score = (
      (done_scope_count.positive? ? 20.0 : 0.0) +
      (done_with_estimate_pct * 0.40) +
      (done_with_time_taken_pct * 0.40)
    ).round(1)
    ku_band = total_count.zero? ? "No Data" : ku_band_for(ku_score)

    github_metrics ||= empty_team_github_metrics
    cbp_score = score_cbp(
      commit_count: github_metrics.dig(:cbp, :total_commits).to_i,
      lines_changed: github_metrics.dig(:cbp, :total_lines_changed).to_i
    )
    pr_score = score_pr(
      opened_count: github_metrics.dig(:pr, :opened_count).to_i,
      merged_count: github_metrics.dig(:pr, :merged_count).to_i,
      open_count: github_metrics.dig(:pr, :open_count).to_i,
      avg_merge_hours: github_metrics.dig(:pr, :avg_merge_hours).to_f
    )
    review_score = score_review(
      review_count: github_metrics.dig(:review, :review_count).to_i,
      approvals: github_metrics.dig(:review, :approvals).to_i,
      changes_requested: github_metrics.dig(:review, :changes_requested).to_i
    )
    github_composite_score = (
      (ku_score * GITHUB_SCORE_WEIGHTS[:kanban]) +
      (cbp_score * GITHUB_SCORE_WEIGHTS[:cbp]) +
      (pr_score * GITHUB_SCORE_WEIGHTS[:pr]) +
      (review_score * GITHUB_SCORE_WEIGHTS[:review])
    ).round(1)
    github_band = github_metrics[:data_available] ? github_band_for(github_composite_score) : "No Data"

    pp_completion_pct = percentage(done_status_total, total_count).round(1)
    pp_band = total_count.zero? ? "No Data" : pp_band_for(pp_completion_pct)

    risk_reasons = []
    risk_reasons << "No cards in Done in #{sprint.name}" if sprint_done_count.zero?
    if !in_current_sprint && cards_missing_time_spent.positive?
      risk_reasons << "#{cards_missing_time_spent} done cards missing Time Spent"
    end

    {
      sprint_name: sprint.name,
      archived_column_exists: board_health.archived_column_exists,
      backlog_cards: columns["Backlog"],
      todo_cards: columns["Todo"] + columns["To Do"],
      in_progress_cards: columns["In Progress"],
      done_cards: done_status_total,
      current_board_done_cards: current_board_done_count,
      sprint_done_cards: sprint_done_count,
      done_in_any_sprint_cards: done_in_any_sprint_count,
      archived_cards: archived_count,
      active_now_cards: active_now_count,
      estimated_hours: estimated_hours.round(1),
      time_spent_hours: time_spent_hours.round(1),
      cards_missing_time_spent: cards_missing_time_spent,
      total_cards: total_count,
      ku_score: ku_score,
      ku_band: ku_band,
      ku_done_with_estimate_pct: done_with_estimate_pct.round(1),
      ku_done_with_time_taken_pct: done_with_time_taken_pct.round(1),
      pp_completion_pct: pp_completion_pct,
      pp_band: pp_band,
      github: {
        score: github_composite_score,
        band: github_band,
        cbp_score: cbp_score,
        pr_score: pr_score,
        review_score: review_score,
        kanban_score: ku_score,
        cbp: github_metrics[:cbp],
        pr: github_metrics[:pr],
        review: github_metrics[:review],
        data_available: github_metrics[:data_available],
        missing_data_flags: github_metrics[:missing_data_flags]
      },
      missing_sprint_done: sprint_done_count.zero?,
      at_risk: risk_reasons.any?,
      at_risk_reasons: risk_reasons
    }
  end

  def build_github_sprint_metrics(team_service:, repo:, sprint:, students:)
    return empty_team_github_metrics(missing_data_flags: ["repo_missing"]) if repo.blank?
    return empty_team_github_metrics(repo: repo, missing_data_flags: ["token_unavailable"]) unless team_service.available?

    start_date = sprint.start_date || Date.current.beginning_of_month
    end_date = sprint.end_date || Date.current.end_of_month

    cbp_by_user = team_service.commit_metrics_by_user(repo, start_date, end_date)
    pr_by_user = team_service.pr_metrics_by_user(repo, start_date, end_date)
    review_by_user = team_service.review_metrics_by_user(repo, start_date, end_date)

    per_student = {}
    students.each do |student|
      username = student.github_username.to_s
      next if username.blank?

      cbp = cbp_by_user[username] || GithubService::CBPResult.new(0, 0, 0, 0)
      pr = pr_by_user[username] || GithubService::PRResult.new(0, 0, 0, 0)
      review = review_by_user[username] || GithubService::ReviewResult.new(0, 0, 0)

      per_student[username] = {
        data_available: true,
        missing_data_flags: [],
        cbp: {
          commit_count: cbp.commit_count,
          lines_added: cbp.lines_added,
          lines_removed: cbp.lines_removed,
          lines_changed: cbp.lines_changed
        },
        pr: {
          opened_count: pr.opened_count,
          merged_count: pr.merged_count,
          open_count: pr.open_count,
          avg_merge_hours: pr.avg_merge_hours
        },
        review: {
          review_count: review.review_count,
          approvals: review.approvals,
          changes_requested: review.changes_requested
        }
      }
    end

    cbp_totals = per_student.values.map { |metric| metric[:cbp] }
    pr_totals = per_student.values.map { |metric| metric[:pr] }
    review_totals = per_student.values.map { |metric| metric[:review] }

    {
      data_available: true,
      repo: repo,
      cbp: {
        total_commits: cbp_totals.sum { |metric| metric[:commit_count].to_i },
        total_lines_changed: cbp_totals.sum { |metric| metric[:lines_changed].to_i },
        active_contributors: cbp_totals.count { |metric| metric[:commit_count].to_i.positive? }
      },
      pr: {
        opened_count: pr_totals.sum { |metric| metric[:opened_count].to_i },
        merged_count: pr_totals.sum { |metric| metric[:merged_count].to_i },
        open_count: pr_totals.sum { |metric| metric[:open_count].to_i },
        avg_merge_hours: average(pr_totals.filter_map { |metric| metric[:avg_merge_hours].to_f.positive? ? metric[:avg_merge_hours].to_f : nil })
      },
      review: {
        review_count: review_totals.sum { |metric| metric[:review_count].to_i },
        approvals: review_totals.sum { |metric| metric[:approvals].to_i },
        changes_requested: review_totals.sum { |metric| metric[:changes_requested].to_i }
      },
      missing_data_flags: [],
      per_student: per_student
    }
  rescue StandardError
    empty_team_github_metrics(repo: repo, missing_data_flags: ["github_query_failed"])
  end

  def empty_student_github_metrics(missing_data_flags: ["repo_or_token_missing"], data_available: false)
    {
      data_available: !!data_available,
      missing_data_flags: Array(missing_data_flags),
      cbp: { commit_count: 0, lines_added: 0, lines_removed: 0, lines_changed: 0 },
      pr: { opened_count: 0, merged_count: 0, open_count: 0, avg_merge_hours: 0.0 },
      review: { review_count: 0, approvals: 0, changes_requested: 0 }
    }
  end

  def empty_team_github_metrics(repo: nil, missing_data_flags: [])
    {
      data_available: false,
      repo: repo,
      cbp: { total_commits: 0, total_lines_changed: 0, active_contributors: 0 },
      pr: { opened_count: 0, merged_count: 0, open_count: 0, avg_merge_hours: 0.0 },
      review: { review_count: 0, approvals: 0, changes_requested: 0 },
      missing_data_flags: Array(missing_data_flags),
      per_student: {}
    }
  end

  def score_cbp(commit_count:, lines_changed:)
    commit_component = [commit_count.to_i * 12.0, 60.0].min
    churn_component = [(lines_changed.to_f / 40.0), 40.0].min
    bounded_score(commit_component + churn_component)
  end

  def score_pr(opened_count:, merged_count:, open_count:, avg_merge_hours:)
    opened_component = [opened_count.to_i * 8.0, 35.0].min
    merged_component = [merged_count.to_i * 12.0, 45.0].min
    open_penalty = [open_count.to_i * 4.0, 20.0].min

    merge_velocity_bonus = if avg_merge_hours.to_f.positive?
      [(36.0 / avg_merge_hours.to_f) * 20.0, 20.0].min
    else
      0.0
    end

    bounded_score(opened_component + merged_component + merge_velocity_bonus - open_penalty)
  end

  def score_review(review_count:, approvals:, changes_requested:)
    review_component = [review_count.to_i * 8.0, 55.0].min
    approval_component = [approvals.to_i * 10.0, 35.0].min
    changes_penalty = [changes_requested.to_i * 3.0, 20.0].min

    bounded_score(review_component + approval_component - changes_penalty)
  end

  def github_band_for(score)
    return "Strong" if score >= 85
    return "Solid" if score >= 70
    return "Watch" if score >= 55

    "At Risk"
  end

  def bounded_score(score)
    [[score.to_f, 0.0].max, 100.0].min.round(1)
  end

  def average(values)
    list = Array(values)
    return 0.0 if list.blank?

    (list.sum.to_f / list.size).round(1)
  end

  def ku_band_for(score)
    return "Healthy" if score >= 85
    return "Watch" if score >= 70

    "At Risk"
  end

  def pp_band_for(score)
    return "On Track" if score >= 80
    return "Monitor" if score >= 60

    "Behind"
  end

  def percentage(numerator, denominator)
    return 0.0 if denominator.to_i <= 0

    (numerator.to_f / denominator.to_f) * 100.0
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

  def sprint_in_progress?(sprint)
    today = Date.current
    start_date = sprint.start_date&.to_date
    end_date = sprint.end_date&.to_date
    return false if start_date.blank? || end_date.blank?

    today >= start_date && today <= end_date
  end

  def numeric_field(card, *candidate_names)
    fields = card.fields || {}
    key = fields.keys.find do |field_name|
      candidate_names.any? { |candidate| field_name.to_s.casecmp(candidate).zero? }
    end

    # Fallback matching handles light naming variations such as
    # "Time Taken (hrs)" vs "Time Taken".
    if key.blank?
      normalized_candidates = candidate_names.map { |name| normalize_field_name(name) }
      key = fields.keys.find do |field_name|
        normalized_field = normalize_field_name(field_name)
        normalized_candidates.any? do |candidate|
          normalized_field.include?(candidate) || candidate.include?(normalized_field)
        end
      end
    end

    return 0.0 if key.blank?

    fields[key].to_f
  end

  def estimate_value(card)
    numeric_field(
      card,
      "Time Estimate",
      "Time Estiamte",
      "Estimate",
      "Estimated Hours",
      "Estimated Time"
    )
  end

  def spent_value(card)
    numeric_field(
      card,
      "Time Spent",
      "Time Taken",
      "Hours Spent",
      "Spent",
      "Actual Time",
      "Time Logged"
    )
  end

  def card_time_sample(card)
    {
      title: card.title,
      status: card.status,
      assignees: Array(card.assignees),
      estimate_field: matched_field_name(card, "Time Estimate", "Time Estiamte", "Estimate", "Estimated Hours", "Estimated Time"),
      estimate_value: estimate_value(card),
      taken_field: matched_field_name(card, "Time Spent", "Time Taken", "Hours Spent", "Spent", "Actual Time", "Time Logged"),
      taken_value: spent_value(card)
    }
  end

  def matched_field_name(card, *candidate_names)
    fields = card.fields || {}
    key = fields.keys.find do |field_name|
      candidate_names.any? { |candidate| field_name.to_s.casecmp(candidate).zero? }
    end

    if key.blank?
      normalized_candidates = candidate_names.map { |name| normalize_field_name(name) }
      key = fields.keys.find do |field_name|
        normalized_field = normalize_field_name(field_name)
        normalized_candidates.any? do |candidate|
          normalized_field.include?(candidate) || candidate.include?(normalized_field)
        end
      end
    end

    key
  end

  def normalize_field_name(value)
    value.to_s.downcase.gsub(/[^a-z0-9]/, "")
  end

  def cards_for_sprint(cards, sprint)
    matching_cards = cards.select { |card| card_matches_sprint?(card, sprint) }
    return matching_cards if matching_cards.any?

    return [] unless sprint_in_progress?(sprint)

    # Fallback only for the active sprint when cards are not explicitly tagged.
    # This prevents Sprint 4 from inheriting Sprint 3 values.
    cards.select do |card|
      status = card.status.to_s
      %w[Backlog Todo To\ Do In\ Progress Done].include?(status)
    end
  end

  def card_matches_sprint?(card, sprint)
    return false if card.blank? || sprint.blank?

    status = card.status.to_s
    return true if done_in_sprint_status?(status, sprint.name)

    sprint_number = sprint.name.to_s[/\d+/]
    return false if sprint_number.blank?

    card.fields.any? do |field_name, value|
      next false unless field_name.to_s.match?(/sprint|iteration/i)

      normalized = value.to_s.downcase
      normalized.include?("sprint #{sprint_number}") || normalized == sprint_number
    end
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
